var HDWalletProvider = require("truffle-hdwallet-provider");

var infura_apikey = "<infure api key redacted>";
var mnemonic = "<mnemonic redacted>";

module.exports = {
  networks: {
    development: {
      host: "localhost",
      port: 8545,
      network_id: "*" // Match any network id
    },
    live: {
      network_id: 1,
      host: "localhost",
      port: 8546   // Different than the default below
    },
    rinkeby: {
      host: "localhost", // Connect to geth on the specified
      port: 8545,
      from: "0xDF144F02408bEae1649741C0d992a39c2FF152C7", // default address to use for any transaction Truffle makes during migrations
      network_id: 4,
      gas: 4612388 // Gas limit used for deploys
    },

    infura_rinkeby: {
      provider: new HDWalletProvider(mnemonic, "https://rinkeby.infura.io/" + infura_apikey),
      network_id: 4,
      from: "0xDF144F02408bEae1649741C0d992a39c2FF152C7" // default address to use for any transaction Truffle makes during migrations
    },

    infura_ropsten_2: {
      provider: new HDWalletProvider(mnemonic, "https://ropsten.infura.io/" + infura_apikey),
      network_id: 3
    },

    infura_mainnet: {
      provider: new HDWalletProvider(mnemonic, "https://mainnet.infura.io/" + infura_apikey),
      network_id: 1
    },

    ropsten: {
      host: "localhost",
      port: 8545,
      network_id: "3",
      gas: 500000
    }
  }
};
