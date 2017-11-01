var EthQuiz = artifacts.require("./EthQuiz.sol");

module.exports = function(deployer) {
  deployer.deploy(EthQuiz);
};
