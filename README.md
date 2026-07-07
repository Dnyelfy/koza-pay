# 🐛 KozaPay — Confidential Payroll & Recallable Payments on Zama FHEVM

> *"Koza" means cocoon in Turkish — what's inside stays hidden until it's ready.*

KozaPay is a confidential payment dApp built on **Zama FHEVM** (Ethereum Sepolia). Payment amounts are encrypted end-to-end using Fully Homomorphic Encryption:

**The chain is public. The amounts are not.**

## Features

- 🔒 **Encrypted balances** — balances are stored on-chain as `euint64` ciphertext. Only the owner can decrypt, client-side, gated by the on-chain ACL.
- ↩️ **Recallable payments** — payments sit in escrow. The recipient claims, or the sender recalls any time before that. Observers see *that* a payment happened, never *how much*.
- 👥 **Confidential payroll** — pay up to 20 recipients in one transaction. All amounts are encrypted in a single batch proof. Each recipient can only decrypt **their own** salary. Coworkers can't see each other's amounts. Nobody else can see anything.
- 🧮 **Encrypted balance checks** — insufficient-balance checks happen homomorphically (`FHE.le` + `FHE.select`), so even a failed payment leaks zero information about the balance.

## Stack

| Layer | Tech |
|---|---|
| Contract | Solidity + `@fhevm/solidity` v0.11 (`FHE.sol`, `ZamaEthereumConfig`) |
| Network | Ethereum Sepolia (Zama FHEVM coprocessor) |
| Frontend | Single-file HTML + ethers v6 + `@zama-fhe/relayer-sdk` v0.4.4 (self-hosted UMD) |
| Decryption | Zama Relayer `userDecrypt` (EIP-712 signed, ACL-gated) |

## Deploy it yourself

### 1. Deploy the contract (Remix)

1. Open [remix.ethereum.org](https://remix.ethereum.org)
2. Create `KozaPay.sol` and paste `contracts/KozaPay.sol`
3. Compile with Solidity **0.8.27** (Remix auto-installs `@fhevm/solidity` from the import)
4. Deploy with **Injected Provider — MetaMask** on **Sepolia**
5. Copy the deployed contract address

### 2. Frontend

1. Open `index.html` and set:
   ```js
   const CONTRACT_ADDRESS = "0xYourDeployedAddress";
   ```
2. Push the repo to GitHub and import it into Vercel (framework preset: **Other**, no build step)

> ⚠️ Keep `relayer-sdk-js.umd.cjs`, `tfhe_bg.wasm`, `kms_lib_bg.wasm`, `workerHelpers.js` and `vercel.json` at the **repo root** — the SDK resolves the wasm files from the site root, and `vercel.json` sets the correct MIME types.

### 3. Use it

1. Connect MetaMask (auto-switches to Sepolia)
2. Claim the faucet → 10,000 encrypted KOZA
3. Send a recallable payment, or run a payroll
4. Decrypt amounts locally — one EIP-712 signature per session

## How privacy works

```
amount (plaintext, browser)
   │  relayer-sdk: createEncryptedInput().add64().encrypt()
   ▼
ciphertext handle + ZK input proof ──► KozaPay.sol
   │  FHE.fromExternal → FHE.le / FHE.select / FHE.sub  (all homomorphic)
   ▼
escrow ciphertext, ACL = { contract, sender, recipient }
   │  recipient: userDecrypt (EIP-712 signature → Relayer → KMS)
   ▼
plaintext amount — only ever exists in the authorized user's browser
```

---

Built by [@Dnyelfy](https://x.com/Dnyelfy) · [#ZamaDeveloperProgram](https://x.com/search?q=%23ZamaDeveloperProgram)
