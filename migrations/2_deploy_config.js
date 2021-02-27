const WETH9 = artifacts.require("WETH9");
const XNum = artifacts.require('XNum.sol');
const XMath = artifacts.require('XMath.sol');
const XConfig = artifacts.require('XConfig');
const XPoolCreator = artifacts.require('XPoolCreator');

module.exports = async function (deployer, network, accounts) {
    //deploy WETH9
    await deployer.deploy(WETH9);

    //deploy XConfig
    const weth = await WETH9.deployed();
    await deployer.deploy(XConfig, weth.address);

    await deployer.deploy(XNum);
    await deployer.link(XNum, XPoolCreator);

    await deployer.deploy(XMath);
    await deployer.link(XMath, XPoolCreator);

    //deploy XPoolCreator
    await deployer.deploy(XPoolCreator);
};
