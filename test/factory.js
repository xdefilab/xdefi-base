const XPool = artifacts.require('XPool');
const XFactory = artifacts.require('XFactory');
const TToken = artifacts.require('TToken');
const truffleAssert = require('truffle-assertions');

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

        it('fails nonAdmin calls collect', async () => {
            await truffleAssert.reverts(factory.collect(nonAdmin, { from: nonAdmin }), 'Not Authorized');
        });

        it('admin collects fees', async () => {
            await pool.bind(WETH, toWei('5'), toWei('5')); //50% WETH
            await pool.bind(DAI, toWei('200'), toWei('5'));//50% DAI

            await pool.finalize();

            await pool.joinPool(toWei('10'), [MAX, MAX], { from: nonAdmin });
            await pool.exitPool(toWei('10'), [toWei('0'), toWei('0')], { from: nonAdmin });

            // Exit fee = 0 so this wont do anything
            await factory.collect(POOL);

            const adminBalance = await pool.balanceOf(admin);
            assert.equal(fromWei(adminBalance), '100');
        });

        it('nonadmin cant set core address', async () => {
            await truffleAssert.reverts(factory.setCore(nonAdmin, { from: nonAdmin }), 'Not Authorized');
        });

        it('admin changes core address', async () => {
            let result = await factory.setCore(user2);
            truffleAssert.eventEmitted(result, "SET_CORE");

            const core = await factory.getCore();
            assert.equal(core, user2);
        });
    });
});
