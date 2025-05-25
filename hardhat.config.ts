import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-verify";
require("dotenv").config();

const config: HardhatUserConfig = {
  solidity: "0.8.26",
  networks: {
    baseSepolia: {
      url: process.env.QUICK_NODE_URL,
      accounts: [process.env.PRIVATE_KEY!]
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY
  }
};

export default config;