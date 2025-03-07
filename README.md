# RealEstateNFTs
Blockchain-powered real estate platform that enables users to buy fractional property ownership as NFTs, purchasable via USDT or ETH.

## Deployment Details  
- **Network:** Ethereum Mainnet  
- **Contract Address:** `0x392cf05207223d409bce6da62a5ba85dccbe8820`  
- **Block Explorer:** [Etherscan Link](https://etherscan.io/address/0x392cf05207223d409bce6da62a5ba85dccbe8820)

## Description 
Da1RealTech is an innovative real estate platform that leverages blockchain technology to enable fractional property ownership. Instead of purchasing entire properties, users can buy shares (fractions) of real estate assets as NFTs. Each property is divided into a fixed number of fractions, with each fraction having a price set in USDT. Users can invest in real estate by purchasing these fractions using either USDT or ETH. By utilizing smart contracts, Da1RealTech ensures transparent, secure, and immutable transactions, making real estate investment accessible to a broader audience.

## Challenges 
-  **Handling Purchases in ETH for USDT-Priced Properties :** Since the properties were listed in USDT, enabling users to purchase them using ETH created the challenge of converting the ETH amount accurately in real time.

- **ETH Price Fluctuation :** There was a potential issue due to exchange rate fluctuations between the time when the user initiated the transaction and when the contract verified the ETH amount. This could cause slight differences in the ETH amount, leading to the risk of overpayment or failed transaction .

## Solutions 
- **Real-Time ETH Conversion Using Chainlink Price Feed :** To address the first challenge, we integrated Chainlink Price Feed (Oracle Service) to fetch the latest USDT/ETH exchange rate. This allowed us to convert the USDT price into ETH and ensure secure and accurate ETH payments, preventing price manipulation .

- **Slippage Tolerance Mechanism :** To tackle ETH price fluctuations, we implemented a slippage tolerance mechanism:

    - If the received ETH (after deducting the slippage percentage) was still lower than the required amount, the transaction would be reverted.
    - If the received ETH was greater, the excess amount would be refunded back to the user, ensuring they only pay the required amount.

This approach allowed for secure and fair transactions, preventing losses from price volatility while ensuring a user-friendly refund process.

## Technical Aspects:
- **Backend :** Developed the backend for [website url](https://app.da1realtech.com/) and admin panel .
- **Node.js & Express.js :** Utilized Node.js for backend services and Express.js for API development.
- **Firebase Integration :** Integrated Firebase for push notifications.
- **Database Management :** Used MongoDB for database management.
- **S3 Bucket :** Used s3 Bucket to keep the Documents + Images of properties.
- **Smart Contracts :** Deployed smart contracts on sepolia (testnet) and Ethereum mainnet for live operations.
  
## Role
- **Lead Blockchain & Backend Developer**: Led the blockchain and backend development of the project.
- **Client Communication & Requirement Gathering**: Managed client communication and gathered project requirements.
