const truffleAssert = require('truffle-assertions');
const { address } = require('./utils/Ethereum');
const XPool = artifacts.require('XPool');
const XFactory = artifacts.require('XFactory');
const TToken = artifacts.require('TToken');
const swapFee = 10 ** -1; // 0.001;

contract('XPool', async (accounts) => {
    const admin = accounts[0];
    const minter = accounts[1];
    const referrer = accounts[2];

    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    let AAA; let BBB; let CCC; let DDD; let EEE; let FFF; let GGG; let HHH; let ZZZ; // addresses
    let aaa; let bbb; let ccc; let ddd; let eee; let fff; let ggg; let hhh; let zzz; // TTokens
    let factory; // XPool factory
    let FACTORY; // factory address
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    before(async () => {
        factory = await XFactory.deployed();
        FACTORY = factory.address;

        POOL = await factory.newXPool.call();
        await factory.newXPool();
        pool = await XPool.at(POOL);

        aaa = await TToken.new('AAA', 'AAA', 18, minter);
        bbb = await TToken.new('BBB', 'BBB', 18, minter);
        ccc = await TToken.new('CCC', 'CCC', 18, minter);
        ddd = await TToken.new('DDD', 'EEE', 18, minter);
        eee = await TToken.new('EEE', 'EEE', 18, minter);
        fff = await TToken.new('FFF', 'FFF', 18, minter);
        ggg = await TToken.new('GGG', 'GGG', 18, minter);
        hhh = await TToken.new('HHH', 'HHH', 18, minter);
        zzz = await TToken.new('ZZZ', 'ZZZ', 18, minter);

        AAA = aaa.address;
        BBB = bbb.address;
        CCC = ccc.address;
        DDD = ddd.address;
        EEE = eee.address;
        FFF = fff.address;
        GGG = ggg.address;
        HHH = hhh.address;
        ZZZ = zzz.address;

        // Admin balances
        await aaa.mint(admin, toWei('100'), { from: minter });
        await bbb.mint(admin, toWei('100'), { from: minter });
        await ccc.mint(admin, toWei('100'), { from: minter });
        await ddd.mint(admin, toWei('100'), { from: minter });
        await eee.mint(admin, toWei('100'), { from: minter });
        await fff.mint(admin, toWei('100'), { from: minter });
        await ggg.mint(admin, toWei('100'), { from: minter });
        await hhh.mint(admin, toWei('100'), { from: minter });
        await zzz.mint(admin, toWei('100'), { from: minter });
    });

    describe('Binding Tokens', () => {
        it('Admin approves tokens', async () => {
            await aaa.approve(POOL, MAX);
            await bbb.approve(POOL, MAX);
            await ccc.approve(POOL, MAX);
            await ddd.approve(POOL, MAX);
            await eee.approve(POOL, MAX);
            await fff.approve(POOL, MAX);
            await ggg.approve(POOL, MAX);
            await hhh.approve(POOL, MAX);
            await zzz.approve(POOL, MAX);
        });

        it('Admin binds tokens', async () => {
            await aaa.transfer(POOL, toWei('50'));
            await pool.bind(AAA, toWei('1'));

            await bbb.transfer(POOL, toWei('50'));
            await pool.bind(BBB, toWei('3'));

            await ccc.transfer(POOL, toWei('50'));
            await pool.bind(CCC, toWei('2.5'));

            await ddd.transfer(POOL, toWei('50'));
            await pool.bind(DDD, toWei('7'));

            await eee.transfer(POOL, toWei('50'));
            await pool.bind(EEE, toWei('10'));

            await fff.transfer(POOL, toWei('50'));
            await pool.bind(FFF, toWei('1.99'));

            await ggg.transfer(POOL, toWei('40'));
            await pool.bind(GGG, toWei('6'));

            await hhh.transfer(POOL, toWei('50'));
            await pool.bind(HHH, toWei('2.1'));

            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(33.59, fromWei(totalDernomWeight));
        });

        it('Fails binding more than 8 tokens', async () => {
            await zzz.transfer(POOL, toWei('50'));
            await truffleAssert.reverts(pool.bind(ZZZ, toWei('2')), 'ERR_MAX_TOKENS');
        });

        it('Fails gulp on unbound token', async () => {
            await truffleAssert.reverts(pool.gulp(ZZZ), 'ERR_NOT_BOUND');
        });

        it('Pool can gulp tokens', async () => {
            await ggg.transferFrom(admin, POOL, toWei('10'));

            await pool.gulp(GGG);
            const balance = await pool.getBalance(GGG);
            assert.equal(fromWei(balance), 50);
        });

        it('Fails swapExactAmountIn with limits', async () => {
            await pool.finalize(toWei(String(swapFee)));// 0.1%;

            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('0'),
                    toWei('0.9')
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('2'),
                    toWei('3.5')
                ),
                'ERR_LIMIT_OUT',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountIn(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('0'),
                    toWei('3.00001')
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
        });

        it('Fails swapExactAmountOut with limits', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    AAA,
                    toWei('51'),
                    BBB,
                    toWei('40'),
                    toWei('5')
                ),
                'ERR_MAX_OUT_RATIO',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    AAA,
                    toWei('5'),
                    BBB,
                    toWei('1'),
                    toWei('1')
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    AAA,
                    toWei('1'),
                    BBB,
                    toWei('1'),
                    toWei('5')
                ),
                'ERR_LIMIT_IN',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(
                    AAA,
                    toWei('5'),
                    BBB,
                    toWei('1'),
                    toWei('3.00001')
                ),
                'ERR_BAD_LIMIT_PRICE',
            );
        });
    });
});
