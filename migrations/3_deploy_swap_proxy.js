const XSwapProxyV1 = artifacts.require("XSwapProxyV1");
const WETH9 = artifacts.require("WETH9");
const TTokenFactory = artifacts.require("TTokenFactory");

module.exports = async function (deployer, network, accounts) {
    if (network == 'development' || network == 'coverage') {
        await deployer.deploy(WETH9);
        await deployer.deploy(XSwapProxyV1, WETH9.address);
        await deployer.deploy(TTokenFactory);
    } else if (network == 'kovan') {
        deployer.deploy(XSwapProxyV1, '0xd0A1E359811322d97991E03f863a0C30C2cF029C');
    }
}
