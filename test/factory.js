const XPool = artifacts.require('XPool');
const XFactory = artifacts.require('XFactory');
const TToken = artifacts.require('TToken');
const truffleAssert = require('truffle-assertions');
const XPoolCreator = artifacts.require('XPoolCreator');

const swapFee = 0.001; // 0.1%;
const exitFee = 0;

contract('XFactory', async (accounts) => {
    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const { hexToUtf8 } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    describe('Factory', () => {
        let factory;
        let pool;
        let POOL;
        let WETH;
        let DAI;
        let weth;
        let dai;

        before(async () => {
            factory = await XFactory.deployed();
            const poolCreator = await XPoolCreator.deployed();
            await factory.setPoolCreator(poolCreator.address);

            weth = await TToken.new('Wrapped Ether', 'WETH', 18, admin);
            dai = await TToken.new('Dai Stablecoin', 'DAI', 18, admin);

            WETH = weth.address;
            DAI = dai.address;

            // admin balances
            await weth.mint(admin, toWei('5'));
            await dai.mint(admin, toWei('200'));

            // nonAdmin balances
            await weth.mint(nonAdmin, toWei('1'), { from: admin });
            await dai.mint(nonAdmin, toWei('50'), { from: admin });

            POOL = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool = await XPool.at(POOL);

            await weth.approve(POOL, MAX);
            await dai.approve(POOL, MAX);

            await weth.approve(POOL, MAX, { from: nonAdmin });
            await dai.approve(POOL, MAX, { from: nonAdmin });
        });

        it('XFactory is APOLLO release', async () => {
            const color = await factory.getVersion();
            assert.equal(hexToUtf8(color), 'APOLLO');
        });

        it('isPool on non pool returns false', async () => {
            const isXPool = await factory.isPool(admin);
            assert.isFalse(isXPool);
        });

        it('isPool on pool returns true', async () => {
            const isXPool = await factory.isPool(POOL);
            assert.isTrue(isXPool);
        });

        it('admin collects fees', async () => {
            await weth.transfer(POOL, toWei('5'));
            await dai.transfer(POOL, toWei('200'));

            await pool.bind(WETH, toWei('5')); //50% WETH
            await pool.bind(DAI, toWei('5'));//50% DAI

            const swapFeeValue = toWei(String(swapFee));
            const exitFeeValue = toWei(String(exitFee));

            pool.setExitFee(exitFeeValue);

            await pool.finalize(swapFeeValue);

            await pool.joinPool(toWei('10'), [MAX, MAX], { from: nonAdmin });
            await pool.exitPool(toWei('10'), [toWei('0'), toWei('0')], { from: nonAdmin });

            // Exit Fee = 0 so this wont do anything
            const adminBalance = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBalance), '100');
        });
    });
});
