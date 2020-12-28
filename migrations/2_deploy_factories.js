const TMath = artifacts.require('TMath');
const XNum = artifacts.require('XNum.sol');
const XMath = artifacts.require('XMath.sol');
const XFactory = artifacts.require('XFactory');

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(XNum);
    await deployer.link(XNum, XFactory);

    await deployer.deploy(XMath);
    await deployer.link(XMath, XFactory);

    if (network === 'development' || network === 'coverage') {
        await deployer.deploy(TMath);
    }
    await deployer.deploy(XFactory);
};
