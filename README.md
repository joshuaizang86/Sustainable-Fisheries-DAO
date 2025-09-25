# 🐟 Sustainable Fisheries DAO

> A decentralized autonomous organization for transparent and sustainable fishing quota management on the Stacks blockchain

## 🌊 Overview

The Sustainable Fisheries DAO is a blockchain-based solution that addresses overfishing and poor quota enforcement through transparent, community-managed fishing quotas. Licensed fishers receive fishing quotas as NFTs, and smart contracts automatically enforce catch limits while rewarding sustainable practices.

## ✨ Key Features

- **🎣 Fisher Registration**: Community members can register as licensed fishers
- **📜 NFT Quotas**: Fishing quotas issued as non-fungible tokens with species-specific limits
- **📊 Catch Reporting**: Transparent catch volume logging with oracle verification
- **🔒 Automatic Enforcement**: Smart contracts freeze quotas when limits are reached
- **🏆 Rewards System**: Token incentives for honest reporting and sustainable practices
- **⚖️ Penalty System**: Automated penalties for violations and false reporting
- **👥 Oracle Network**: Trusted inspectors verify catch reports

## 🚀 Contract Architecture

### Tokens
- **Fishing Quota NFTs**: Unique tokens representing fishing rights
- **Fisheries Tokens**: Fungible tokens for rewards and penalties

### Core Data Structures
- **Fishers**: Registration status, reputation, catch history, violations
- **Quotas**: Species limits, seasonal restrictions, current usage
- **Catch Reports**: Verified catch submissions with oracle validation
- **Oracle Network**: Authorized inspectors and government certifiers

## 📋 Usage Instructions

### For Fishers

#### 1. Register as a Fisher 🎣
```clarity
(contract-call? .sustainable-fisheries-dao register-fisher)
```
- Receive 1000 fisheries tokens upon registration
- Initial reputation score of 100

#### 2. Report Your Catch 📊
```clarity
(contract-call? .sustainable-fisheries-dao report-catch u1 u50)
```
- Parameters: `quota-id` and `catch-amount`
- Must be within quota limits and fishing season

#### 3. Check Your Status 📈
```clarity
(contract-call? .sustainable-fisheries-dao get-fisher-info 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### For Contract Owner

#### 1. Issue Fishing Quota 📜
```clarity
(contract-call? .sustainable-fisheries-dao issue-quota 
  'ST1FISHER... 
  "tuna" 
  u1000 
  u100 
  u200)
```
- Parameters: `fisher`, `species`, `max-catch`, `season-start`, `season-end`

#### 2. Add Oracle Inspector 👥
```clarity
(contract-call? .sustainable-fisheries-dao add-oracle 'ST1ORACLE...)
```

### For Oracles

#### 1. Verify Catch Reports ✅
```clarity
(contract-call? .sustainable-fisheries-dao verify-catch-report u1)
```

#### 2. Reward Sustainable Practices 🏆
```clarity
(contract-call? .sustainable-fisheries-dao reward-sustainable-practice 
  'ST1FISHER... 
  u200)
```

#### 3. Penalize Violations ⚖️
```clarity
(contract-call? .sustainable-fisheries-dao penalize-fisher 
  'ST1FISHER... 
  "overfishing")
```

## 🔍 Read-Only Functions

### Check Quota Utilization
```clarity
(contract-call? .sustainable-fisheries-dao get-quota-utilization u1)
```
Returns percentage of quota used (0-100)

### View Contract Statistics
```clarity
(contract-call? .sustainable-fisheries-dao get-contract-stats)
```
Returns total quotas, reports, treasury balance, and settings

### Get Fisher's Quotas
```clarity
(contract-call? .sustainable-fisheries-dao get-fisher-quotas 'ST1FISHER...)
```

## 🛡️ Security & Governance

### Access Control
- **Contract Owner**: Issues quotas, manages oracles, updates settings
- **Oracles**: Verify reports, issue rewards/penalties
- **Fishers**: Report catches within their quotas

### Penalty System
- **3 strikes rule**: Fishers deactivated after 3 violations
- **Token slashing**: Penalty tokens burned from violator's balance
- **Reputation system**: Dynamic reputation scoring affects privileges

### Treasury Management
- Penalties contribute to community treasury
- Rewards distributed from treasury balance
- Sustainable practice incentives

## 🌍 Environmental Impact

### Conservation Benefits
- **Transparent Quotas**: Eliminate corruption in quota allocation
- **Real-time Monitoring**: Prevent overfishing through automated limits
- **Community Enforcement**: Peer-to-peer reporting and verification
- **Biodiversity Protection**: Species-specific quota management

### Economic Benefits
- **Fair Access**: Equitable marine resource distribution
- **Livelihood Security**: Sustainable income for fishing communities
- **Reduced Costs**: Eliminate expensive monitoring middlemen
- **Trust Building**: Transparent, tamper-proof record keeping

## 🧪 Testing

Run the test suite:
```bash
npm install
npm test
```

## 📄 License

This project is open source and available under the MIT License.

## 🤝 Contributing

We welcome contributions from the community! Please see our contributing guidelines for more information.

---

*Building a sustainable future for our oceans, one smart contract at a time* 🌊🐟
