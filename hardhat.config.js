/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts", // Path to your contracts folder
    tests: "./test", // Path to your tests folder
  },
};
