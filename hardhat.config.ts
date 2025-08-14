import * as dotenv from "dotenv";
import { task } from "hardhat/config";
import "@nomiclabs/hardhat-ethers";
import { HardhatUserConfig } from "hardhat/types";
import "hardhat-deploy";
import "hardhat-gas-reporter";
import "@typechain/hardhat";
import "solidity-coverage";
import { node_url, accounts } from "./utils/network";
import "@nomiclabs/hardhat-etherscan";

dotenv.config();

require("./tasks/generateABI.ts")

// This is a sample Hardhat task. To learn how to create your own go to
// https://hardhat.org/guides/create-task.html
task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }
});

// Constants
const { PRIVATE_KEY, ROPSTEN_PRIVATE_KEY } = process.env;
const DEPLOYER = process.env.DEPLOYER_ADDRESS || null;
const ROPSTEN_DEPLOYER = process.env.ROPSTEN_DEPLOYER_ADDRESS || null;
const {
  ETH_MAINNET_RPC_URL,
  FTM_MAINNET_RPC_URL,
  BSC_MAINNET_RPC_URL,
  AVAX_MAINNET_RPC_URL,
  POLYGON_MAINNET_RPC_URL,
  ARBITRUM_MAINNET_RPC_URL,
  OPTIMISM_MAINNET_RPC_URL,
  MOONBEAM_MAINNET_RPC_URL,
  MOONRIVER_MAINNET_RPC_URL,
  AURORA_MAINNET_RPC_URL,
  BOBA_MAINNET_RPC_URL,
  CELO_MAINNET_RPC_URL,
  GNOSIS_MAINNET_RPC_URL,
  ROPSTEN_RPC_URL,
  BSC_TESTNET_RPC_URL,
  POLYGON_TESTNET_RPC_URL,
  ETH_GOERLI_TESTNET_RPC_URL,
} = process.env;
const ropstenAccounts = ROPSTEN_PRIVATE_KEY ? [ROPSTEN_PRIVATE_KEY] : [];
const PKEY = process.env.PRIVATE_KEY || null;

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.25",
        settings: {
          // viaIR: true,
          optimizer: {
            enabled: true,
            runs: 10000,
          },
        },
      },
    ],
  },

  namedAccounts: {
    deployer: 0,
  },
  networks: {
    hardhat: {
      accounts: [{privateKey: PKEY!!, balance: "100000000000000000000"}],
      forking: {
        url: "https://mainnet.infura.io/v3/acc5b1da0bab4d33a5fa171b7b6c1921",
        blockNumber: 16438518
      },
      saveDeployments: true
    },
    bsc_testnet: {
      url: BSC_TESTNET_RPC_URL,
      chainId: 97,
      accounts: PKEY ? [PKEY] : accounts("bsc_test"),
    },
    polygon_testnet: {
      url: POLYGON_TESTNET_RPC_URL,
      chainId: 80001,
      accounts: PKEY ? [PKEY] : accounts("polygon_test"),
      gasMultiplier: 4,
    },
    eth: {
      url: ETH_MAINNET_RPC_URL,
      chainId: 1,
      accounts: PKEY ? [PKEY] : accounts("eth"),
      gasMultiplier: 3,
    },
    ftm: {
      url: FTM_MAINNET_RPC_URL,
      chainId: 250,
      accounts: PKEY ? [PKEY] : accounts("ftm"),
      gasMultiplier: 4,
      // gasPrice: 20000000000,
      // gas: 6000000,
    },
    bsc: {
      url: BSC_MAINNET_RPC_URL,
      chainId: 56,
      accounts: PKEY ? [PKEY] : accounts("bsc"),
      gasMultiplier: 3,
    },
    avax: {
      url: AVAX_MAINNET_RPC_URL,
      chainId: 43114,
      accounts: PKEY ? [PKEY] : accounts("avax"),
      gasMultiplier: 3,
    },
    polygon: {
      url: POLYGON_MAINNET_RPC_URL,
      chainId: 137,
      accounts: PKEY ? [PKEY] : accounts("polygon"),
      gasMultiplier: 6,
    },
    arbitrum: {
      url: ARBITRUM_MAINNET_RPC_URL,
      chainId: 42161,
      accounts: PKEY ? [PKEY] : accounts("arbitrum"),
      gasMultiplier: 3,
    },
    optimism: {
      url: OPTIMISM_MAINNET_RPC_URL,
      chainId: 10,
      accounts: PKEY ? [PKEY] : accounts("optimism"),
      gasMultiplier: 3,
    },
    moonbeam: {
      url: MOONBEAM_MAINNET_RPC_URL,
      chainId: 1284,
      accounts: PKEY ? [PKEY] : accounts("moonbeam"),
      gasMultiplier: 3,
    },
    moonriver: {
      url: MOONRIVER_MAINNET_RPC_URL,
      chainId: 1285,
      accounts: PKEY ? [PKEY] : accounts("moonriver"),
      gasMultiplier: 3,
    },
    aurora: {
      url: AURORA_MAINNET_RPC_URL,
      chainId: 1313161554,
      accounts: PKEY ? [PKEY] : accounts("aurora"),
      gasMultiplier: 3,
    },
    boba: {
      url: BOBA_MAINNET_RPC_URL,
      chainId: 288,
      accounts: PKEY ? [PKEY] : accounts("boba"),
      gasMultiplier: 3,
    },
    celo: {
      url: CELO_MAINNET_RPC_URL,
      chainId: 42220,
      accounts: PKEY ? [PKEY] : accounts("celo"),
      gasMultiplier: 3,
    },
    gnosis: {
      url: GNOSIS_MAINNET_RPC_URL,
      chainId: 100,
      accounts: PKEY ? [PKEY] : accounts("gnosis"),
      gasMultiplier: 3,
    },
    goerli: {
      url: ETH_GOERLI_TESTNET_RPC_URL,
      chainId: 5,
      accounts: PKEY ? [PKEY] : accounts("goerli"),
      gasMultiplier: 5000,
    },
  },
  gasReporter: {
    currency: "USD",
    gasPrice: 100,
    enabled: process.env.REPORT_GAS ? true : false,
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
    maxMethodDiff: 10,
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v5",
  },
  etherscan: {
    apiKey: {
      eth: process.env.ETHERSCAN_API_KEY || "",
      mainnet: process.env.ETHERSCAN_API_KEY || "",
      goerli: process.env.ETHERSCAN_API_KEY || "",
      opera: process.env.FTM_ETHERSCAN_API_KEY || "",
      bsc: process.env.BSC_ETHERSCAN_API_KEY || "",
      bscTestnet: process.env.BSC_ETHERSCAN_API_KEY || "",
      avax: process.env.POLY_ETHERSCAN_API_KEY || "",
      avalanche: process.env.AVAX_SNOWTRACE_ETHERSCAN_API_KEY || "",
      polygon: process.env.POLYGON_ETHERSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGON_ETHERSCAN_API_KEY || "",
      moonbeam: process.env.MOONBEAM_ETHERSCAN_API_KEY || "",
      moonriver: process.env.MOONRIVER_ETHERSCAN_API_KEY || "",
      arbitrum: process.env.ARBITRUM_ETHERSCAN_API_KEY || "",
      arbitrumOne: process.env.ARBITRUM_ETHERSCAN_API_KEY || "",
      optimism: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
      optimisticEthereum: process.env.OPTIMISM_ETHERSCAN_API_KEY || "",
      aurora: process.env.AURORA_ETHERSCAN_API_KEY || "",
      boba: process.env.BOBA_ETHERSCAN_API_KEY || "",
      celo: process.env.CELO_ETHERSCAN_API_KEY || "",
      gnosis: process.env.GNOSIS_ETHERSCAN_API_KEY || "",
    },
  },
};

export default config;
