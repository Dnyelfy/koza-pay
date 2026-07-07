// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.24;

import {FHE, euint64, externalEuint64, ebool} from "@fhevm/solidity/lib/FHE.sol";
import {ZamaEthereumConfig} from "@fhevm/solidity/config/ZamaConfig.sol";

/// @title KozaPay — Confidential Payroll & Recallable Payments on Zama FHEVM
/// @notice Payment amounts are encrypted end-to-end using FHE.
///         - The chain is public. The amounts are not.
///         - Payments sit in escrow: recipient claims, or sender recalls.
///         - Payroll: pay up to 20 recipients in one tx; each recipient
///           can only decrypt their own amount.
/// @author Dnyelfy
contract KozaPay is ZamaEthereumConfig {
    // ---------------------------------------------------------------
    // Demo unit: KOZA (2 decimals). Faucet mints an encrypted balance.
    // ---------------------------------------------------------------
    uint64 public constant FAUCET_AMOUNT = 10_000_00; // 10,000.00 KOZA

    mapping(address => euint64) private _balances;
    mapping(address => bool) public hasClaimedFaucet;

    enum Status {
        Pending,
        Claimed,
        Recalled
    }

    struct Payment {
        address from;
        address to;
        euint64 amount; // encrypted — only sender & recipient can decrypt
        Status status;
        uint64 createdAt;
        uint256 payrollId; // 0 = single payment
        string memo; // optional public note (never put amounts here)
    }

    Payment[] private _payments;
    mapping(address => uint256[]) private _sentIds;
    mapping(address => uint256[]) private _receivedIds;

    uint256 public payrollCount;

    // ---------------------------------------------------------------
    // Events (no amounts — amounts never leave ciphertext)
    // ---------------------------------------------------------------
    event FaucetClaimed(address indexed user);
    event PaymentCreated(
        uint256 indexed id,
        address indexed from,
        address indexed to,
        uint256 payrollId
    );
    event PaymentClaimed(uint256 indexed id, address indexed to);
    event PaymentRecalled(uint256 indexed id, address indexed from);
    event PayrollCreated(
        uint256 indexed payrollId,
        address indexed from,
        uint256 recipients
    );

    // ---------------------------------------------------------------
    // Faucet
    // ---------------------------------------------------------------
    function claimFaucet() external {
        require(!hasClaimedFaucet[msg.sender], "Faucet already claimed");
        hasClaimedFaucet[msg.sender] = true;

        _balances[msg.sender] = FHE.add(
            _balances[msg.sender],
            FHE.asEuint64(FAUCET_AMOUNT)
        );
        FHE.allowThis(_balances[msg.sender]);
        FHE.allow(_balances[msg.sender], msg.sender);

        emit FaucetClaimed(msg.sender);
    }

    // ---------------------------------------------------------------
    // Single recallable payment
    // ---------------------------------------------------------------
    function sendPayment(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        string calldata memo
    ) external returns (uint256 id) {
        require(to != address(0) && to != msg.sender, "Invalid recipient");

        euint64 amount = FHE.fromExternal(encryptedAmount, inputProof);
        euint64 moved = _escrowFrom(msg.sender, amount);
        id = _createPayment(msg.sender, to, moved, 0, memo);
    }

    // ---------------------------------------------------------------
    // Confidential payroll: one tx, up to 20 recipients.
    // All amounts share ONE input proof (encrypted client-side in a
    // single batch). Each recipient's escrow ciphertext is ACL'd only
    // to sender + that recipient.
    // ---------------------------------------------------------------
    function createPayroll(
        address[] calldata recipients,
        externalEuint64[] calldata encryptedAmounts,
        bytes calldata inputProof,
        string calldata memo
    ) external returns (uint256 payrollId) {
        uint256 n = recipients.length;
        require(n > 0 && n <= 20, "1-20 recipients");
        require(n == encryptedAmounts.length, "Length mismatch");

        payrollCount += 1;
        payrollId = payrollCount;

        for (uint256 i = 0; i < n; i++) {
            address to = recipients[i];
            require(to != address(0) && to != msg.sender, "Invalid recipient");

            euint64 amount = FHE.fromExternal(encryptedAmounts[i], inputProof);
            euint64 moved = _escrowFrom(msg.sender, amount);
            _createPayment(msg.sender, to, moved, payrollId, memo);
        }

        emit PayrollCreated(payrollId, msg.sender, n);
    }

    // ---------------------------------------------------------------
    // Claim / Recall
    // ---------------------------------------------------------------
    function claimPayment(uint256 id) external {
        Payment storage p = _payments[id];
        require(p.to == msg.sender, "Not the recipient");
        require(p.status == Status.Pending, "Not pending");

        p.status = Status.Claimed;
        _creditBalance(msg.sender, p.amount);

        emit PaymentClaimed(id, msg.sender);
    }

    function recallPayment(uint256 id) external {
        Payment storage p = _payments[id];
        require(p.from == msg.sender, "Not the sender");
        require(p.status == Status.Pending, "Not pending");

        p.status = Status.Recalled;
        _creditBalance(msg.sender, p.amount);

        emit PaymentRecalled(id, msg.sender);
    }

    // ---------------------------------------------------------------
    // Internal FHE helpers
    // ---------------------------------------------------------------

    /// @dev Moves `amount` out of sender's encrypted balance into escrow.
    ///      If the (encrypted) amount exceeds the (encrypted) balance,
    ///      the moved value silently becomes 0 — no information about
    ///      the balance is ever revealed.
    function _escrowFrom(
        address sender,
        euint64 amount
    ) internal returns (euint64 moved) {
        euint64 bal = _balances[sender];
        ebool enough = FHE.le(amount, bal);
        moved = FHE.select(enough, amount, FHE.asEuint64(0));

        _balances[sender] = FHE.sub(bal, moved);
        FHE.allowThis(_balances[sender]);
        FHE.allow(_balances[sender], sender);
    }

    function _creditBalance(address user, euint64 amount) internal {
        _balances[user] = FHE.add(_balances[user], amount);
        FHE.allowThis(_balances[user]);
        FHE.allow(_balances[user], user);
    }

    function _createPayment(
        address from,
        address to,
        euint64 moved,
        uint256 payrollId,
        string calldata memo
    ) internal returns (uint256 id) {
        // ACL: contract + sender + recipient. Nobody else can ever decrypt.
        FHE.allowThis(moved);
        FHE.allow(moved, from);
        FHE.allow(moved, to);

        id = _payments.length;
        _payments.push(
            Payment({
                from: from,
                to: to,
                amount: moved,
                status: Status.Pending,
                createdAt: uint64(block.timestamp),
                payrollId: payrollId,
                memo: memo
            })
        );
        _sentIds[from].push(id);
        _receivedIds[to].push(id);

        emit PaymentCreated(id, from, to, payrollId);
    }

    // ---------------------------------------------------------------
    // Views (ciphertext handles only — decryption happens client-side
    // through the Zama Relayer, gated by the on-chain ACL)
    // ---------------------------------------------------------------
    function getBalance(address user) external view returns (euint64) {
        return _balances[user];
    }

    function getPayment(
        uint256 id
    )
        external
        view
        returns (
            address from,
            address to,
            euint64 amount,
            Status status,
            uint64 createdAt,
            uint256 payrollId,
            string memory memo
        )
    {
        Payment storage p = _payments[id];
        return (
            p.from,
            p.to,
            p.amount,
            p.status,
            p.createdAt,
            p.payrollId,
            p.memo
        );
    }

    function getSentIds(address user) external view returns (uint256[] memory) {
        return _sentIds[user];
    }

    function getReceivedIds(
        address user
    ) external view returns (uint256[] memory) {
        return _receivedIds[user];
    }

    function totalPayments() external view returns (uint256) {
        return _payments.length;
    }
}
