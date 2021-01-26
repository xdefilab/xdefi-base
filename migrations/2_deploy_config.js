const XNum = artifacts.require('XNum.sol');
const XMath = artifacts.require('XMath.sol');
const XConfig = artifacts.require('XConfig');
const XPoolCreator = artifacts.require('XPoolCreator');

module.exports = async function (deployer, network, accounts) {
    await deployer.deploy(XConfig);

    await deployer.deploy(XNum);
    await deployer.link(XNum, XPoolCreator);

    await deployer.deploy(XMath);
    await deployer.link(XMath, XPoolCreator);

    await deployer.deploy(XPoolCreator);
};
