const TMath = artifacts.require('TMath');
const XPToken = artifacts.require('XPToken');
const XFactory = artifacts.require('XFactory');

module.exports = async function (deployer, network, accounts) {
    if (network === 'development' || network === 'coverage') {
        deployer.deploy(TMath);
    }
    deployer.deploy(XFactory);
};
