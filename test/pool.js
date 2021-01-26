const truffleAssert = require('truffle-assertions');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');
const { address } = require('./utils/Ethereum');
const XPool = artifacts.require('XPool');
const XFactory = artifacts.require('XFactory');
const TToken = artifacts.require('TToken');
const verbose = process.env.VERBOSE;

const swapFee = 0.0025; // 0.25%;

contract('XPool', async (accounts) => {
    const admin = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const errorDelta = 10 ** -8;
    const MAX = web3.utils.toTwosComplement(-1);

    //token address
    let WETH; let MKR; let DAI; let XXX; // addresses
    let POOL; // pool address

    //instance
    let weth; let mkr; let dai; let xxx; // TTokens
    let factory; // XPool factory
    let pool; // first pool w/ defaults

    //token address
    let AA; let BB; let CC; let DD;
    let aa; let bb; let cc; let dd;

    before(async () => {
        factory = await XFactory.deployed();

        POOL = await factory.newXPool.call();
        await factory.newXPool();
        pool = await XPool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', 18, admin);
        mkr = await TToken.new('Maker', 'MKR', 18, admin);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18, admin);
        xxx = await TToken.new('XXX', 'XXX', 18, admin);

        aa = await TToken.new('XXX', 'XXX', 18, admin);
        bb = await TToken.new('XXX', 'XXX', 18, admin);
        cc = await TToken.new('XXX', 'XXX', 18, admin);
        dd = await TToken.new('XXX', 'XXX', 18, admin);

        WETH = weth.address;
        MKR = mkr.address;
        DAI = dai.address;
        XXX = xxx.address;

        AA = aa.address;
        BB = bb.address;
        CC = cc.address;
        DD = dd.address;

        /*
            Tests assume token prices
            WETH - $200
            MKR  - $500
            DAI  - $1
            XXX  - $0
        */

        // Admin balances
        await weth.mint(admin, toWei('50'));
        await mkr.mint(admin, toWei('20'));
        await dai.mint(admin, toWei('10000'));
        await xxx.mint(admin, toWei('10'));

        await aa.mint(admin, toWei('100'));
        await bb.mint(admin, toWei('100'));
        await cc.mint(admin, toWei('100'));
        await dd.mint(admin, toWei('100'));

        // User1 balances
        await weth.mint(user1, toWei('25'), { from: admin });
        await mkr.mint(user1, toWei('4'), { from: admin });
        await dai.mint(user1, toWei('40000'), { from: admin });
        await xxx.mint(user1, toWei('10'), { from: admin });

        // User2 balances
        await weth.mint(user2, toWei('12.2222'), { from: admin });
        await mkr.mint(user2, toWei('1.015333'), { from: admin });
        await dai.mint(user2, toWei('0'), { from: admin });
        await xxx.mint(user2, toWei('51'), { from: admin });
    });

    describe('Binding Tokens', () => {
        it('Controller is msg.sender', async () => {
            const controller = await pool.controller();
            assert.equal(controller, admin);
        });

        it('Pool starts with no bound tokens', async () => {
            const numTokens = await pool.getNumTokens();
            assert.equal(0, numTokens);
            const isBound = await pool.isBound.call(WETH);
            assert(!isBound);
        });

        it('Fails binding tokens which balance < 0.000001 TOKEN', async () => {
            await aa.transfer(POOL, toWei('1', 'wei'));
            await truffleAssert.reverts(
                pool.bind(AA, toWei('2.5')), 'ERR_MIN_BALANCE');
        });

        it('Admin approves tokens', async () => {
            await weth.approve(POOL, MAX);
            await mkr.approve(POOL, MAX);
            await dai.approve(POOL, MAX);
            await xxx.approve(POOL, MAX);
        });

        it('Fails binding weights and balances outside MIX MAX WEIGHT', async () => {
            await aa.transfer(POOL, toWei('1'));
            await truffleAssert.reverts(pool.bind(AA, toWei('0.99')), 'ERR_MIN_WEIGHT');
            await truffleAssert.reverts(pool.bind(AA, toWei('50.01')), 'ERR_MAX_WEIGHT');
        });

        it('Fails finalizing pool without 2 tokens', async () => {
            const swapFeeValue = toWei(String(swapFee));
            await truffleAssert.reverts(pool.finalize(swapFeeValue), 'ERR_MIN_TOKENS');
        });

        it('Admin binds tokens', async () => {
            // Equal weights WETH, MKR, DAI
            await weth.transfer(POOL, toWei('50'));
            await pool.bind(WETH, toWei('5'));

            await mkr.transfer(POOL, toWei('20'));
            await pool.bind(MKR, toWei('5'));

            await dai.transfer(POOL, toWei('10000'));
            await pool.bind(DAI, toWei('5'));

            const numTokens = await pool.getNumTokens();
            assert.equal(3, numTokens);
            const totalDernomWeight = await pool.getTotalDenormalizedWeight();
            assert.equal(15, fromWei(totalDernomWeight));
            const wethDenormWeight = await pool.getDenormalizedWeight(WETH);
            assert.equal(5, fromWei(wethDenormWeight));
            const wethNormWeight = await pool.getNormalizedWeight(WETH);
            assert.equal(0.333333333333333333, fromWei(wethNormWeight));
            const mkrBalance = await pool.getBalance(MKR);
            assert.equal(20, fromWei(mkrBalance));
        });

        it('Fails binding above MAX TOTAL WEIGHT', async () => {
            await xxx.transfer(POOL, toWei('1'));
            await truffleAssert.reverts(pool.bind(XXX, toWei('36')), 'ERR_MAX_TOTAL_WEIGHT');
        });

        it('Fails binding random token', async () => {
            await truffleAssert.reverts(
                pool.bind(WETH, toWei('1')), 'ERR_IS_BOUND',
            );
        });

        it('Fails getting final tokens before finalized', async () => {
            await truffleAssert.reverts(
                pool.getFinalTokens(), 'ERR_NOT_FINALIZED',
            );
        });
    });

    describe('Finalizing pool', () => {
        it('Fails when other users interact before finalizing', async () => {
            await truffleAssert.reverts(
                pool.bind(WETH, toWei('5'), { from: user1 }), 'ERR_NOT_CONTROLLER',
            );
            await truffleAssert.reverts(
                pool.joinPool(toWei('1'), [MAX, MAX], { from: user1 }), 'ERR_NOT_FINALIZED',
            );
            await truffleAssert.reverts(
                pool.exitPool(toWei('1'), [toWei('0'), toWei('0')], { from: user1 }), 'ERR_NOT_FINALIZED',
            );
        });

        it('Fails calling any swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountIn(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')), 'ERR_NOT_FINALIZED.',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountIn(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')), 'ERR_NOT_FINALIZED.',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(WETH, toWei('2.5'), DAI, toWei('475'), toWei('200')), 'ERR_NOT_FINALIZED',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(DAI, toWei('2.5'), WETH, toWei('475'), toWei('200')), 'ERR_NOT_FINALIZED',
            );
        });

        it('Fails calling any join exit swap before finalizing', async () => {
            await truffleAssert.reverts(
                pool.joinswapExternAmountIn(WETH, toWei('2.5'), toWei('0')), 'ERR_NOT_FINALIZED',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountIn(WETH, toWei('2.5'), toWei('0')), 'ERR_NOT_FINALIZED',
            );
        });

        it('Fails setting swap fee which is not in SWAP_FEES', async () => {
            const swapFeeValue = toWei('0.015'); //1.5%
            await truffleAssert.reverts(
                pool.finalize(swapFeeValue), 'ERR_INVALID_SWAP_FEE',
            );
        });

        it('Fails nonadmin sets fees or controller', async () => {
            await truffleAssert.reverts(
                pool.setController(user1, { from: user1 }), 'ERR_NOT_CONTROLLER',
            );
        });

        it('Fails nonadmin finalizes pool', async () => {
            const swapFeeValue = toWei(String(swapFee));
            await truffleAssert.reverts(
                pool.finalize(swapFeeValue, { from: user1 }), 'ERR_NOT_CONTROLLER',
            );
        });

        it('Admin finalizes pool', async () => {
            const swapFeeValue = toWei(String(swapFee));
            const tx = await pool.finalize(swapFeeValue);
            const adminXPT = await pool.balanceOf(admin);
            assert.equal(100, fromWei(adminXPT));
            truffleAssert.eventEmitted(tx, 'Transfer', (event) => event.dst === admin);
            const finalized = pool.finalized();
            assert(finalized);
        });

        it('Fails finalizing pool after finalized', async () => {
            const swapFeeValue = toWei(String(swapFee));
            await truffleAssert.reverts(
                pool.finalize(swapFeeValue), 'ERR_IS_FINALIZED',
            );
        });

        it('Fails binding new token after finalized', async () => {
            await bb.transfer(POOL, toWei('1'));
            await truffleAssert.reverts(
                pool.bind(BB, toWei('5')), 'ERR_IS_FINALIZED',
            );
        });

        it('Get final pool data', async () => {
            const finalTokens = await pool.getFinalTokens();
            assert.sameMembers(finalTokens, [WETH, MKR, DAI]);

            const numTokens = await pool.getNumTokens();
            assert.equal(3, numTokens);

            const swapFee = await pool.swapFee();
            assert.equal(toWei('0.0025'), swapFee);
        });

        it('Get final weights', async () => {
            const totalWeight = await pool.getTotalDenormalizedWeight();
            const weth_denorm = await pool.getDenormalizedWeight(WETH);
            const mkr_denorm = await pool.getDenormalizedWeight(MKR);
            const dai_denorm = await pool.getDenormalizedWeight(DAI);

            console.log(`totalWeight: ${totalWeight}, weth_denorm: ${weth_denorm}, mkr_denorm: ${mkr_denorm}, dai_denorm: ${dai_denorm}`);
        });
    });

    describe('User interactions', () => {
        it('Other users approve tokens', async () => {
            await weth.approve(POOL, MAX, { from: user1 });
            await mkr.approve(POOL, MAX, { from: user1 });
            await dai.approve(POOL, MAX, { from: user1 });
            await xxx.approve(POOL, MAX, { from: user1 });

            await weth.approve(POOL, MAX, { from: user2 });
            await mkr.approve(POOL, MAX, { from: user2 });
            await dai.approve(POOL, MAX, { from: user2 });
            await xxx.approve(POOL, MAX, { from: user2 });
        });

        it('User1 joins pool', async () => {
            await pool.joinPool(toWei('5'), [MAX, MAX, MAX], { from: user1 });
            const daiBalance = await pool.getBalance(DAI);
            assert.equal(10500, fromWei(daiBalance));
            const userWethBalance = await weth.balanceOf(user1);
            assert.equal(22.5, fromWei(userWethBalance));
        });

        /*
          Current pool balances and denorms
          WETH - 52.5, denorm: 5 
          MKR - 21, denorm: 5 
          DAI - 10,500, denorm: 5 
          XXX - 1
          Swap Fee: 0.25%
        */

        it('getSpotPriceSansFee and getSpotPrice', async () => {
            let weth_balance_pool = await weth.balanceOf(POOL);
            let dai_balance_pool = await dai.balanceOf(POOL);
            let mkr_balance_pool = await mkr.balanceOf(POOL);
            let xxx_balance_pool = await xxx.balanceOf(POOL);
            console.log(`weth_balance_pool: ${weth_balance_pool}, dai_balance_pool: ${dai_balance_pool}, mkr_balance_pool: ${mkr_balance_pool}, xxx_balance_pool: ${xxx_balance_pool}`);

            const wethPrice = await pool.getSpotPriceSansFee(DAI, WETH);
            assert.equal(200, fromWei(wethPrice));

            const wethPriceFee = await pool.getSpotPrice(DAI, WETH);
            const wethPriceFeeCheck = ((10500 / 5) / (52.5 / 5)) * (1 / (1 - 0.025));
            // 200.6018054162487462
            assert.equal(fromWei(wethPriceFee), wethPriceFeeCheck);
        });

        it('Fail swapExactAmountIn unbound or over min max ratios', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountIn(WETH, toWei('2.5'), XXX, toWei('100'), toWei('200'), { from: user2 }),
                'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountIn(WETH, toWei('26.5'), DAI, toWei('5000'), toWei('200'), { from: user2 }),
                'ERR_MAX_IN_RATIO',
            );
        });

        it('swapExactAmountIn without referrer', async () => {
            // 2.5 WETH -> DAI
            const expected = calcOutGivenIn(52.5, 5, 10500, 5, 2.5, 0.025);
            const txr = await pool.swapExactAmountIn(
                WETH,
                toWei('2.5'),
                DAI,
                toWei('475'),
                toWei('200'),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');
            // 475.905805337091423

            const actual = fromWei(log.args[4]);
            const relDif = calcRelativeDiff(expected, actual);
            if (verbose) {
                console.log('swapExactAmountIn');
                console.log(`expected: ${expected})`);
                console.log(`actual: ${actual})`);
                console.log(`relDif: ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            const userDaiBalance = await dai.balanceOf(user2);
            assert.equal(fromWei(userDaiBalance), Number(fromWei(log.args[4])));

            // 182.804672101083406128
            const wethPrice = await pool.getSpotPrice(DAI, WETH);
            const wethPriceFeeCheck = ((10024.094194662908577 / 5) / (55 / 5)) * (1 / (1 - 0.025));
            assert.approximately(Number(fromWei(wethPrice)), Number(wethPriceFeeCheck), errorDelta);

            const daiNormWeight = await pool.getNormalizedWeight(DAI);
            assert.equal(0.333333333333333333, fromWei(daiNormWeight));
        });

        //TODO: 'swapExactAmountIn with referrer'

        it('swapExactAmountOut without referrer', async () => {
            // ETH -> 1 MKR
            // const amountIn = (55 * (((21 / (21 - 1)) ** (5 / 5)) - 1)) / (1 - 0.003);
            const expected = calcInGivenOut(55, 5, 21, 5, 1, 0.025);
            const txr = await pool.swapExactAmountOut(
                WETH,
                toWei('3'),
                MKR,
                toWei('1.0'),
                toWei('500'),
                { from: user2 },
            );
            const log = txr.logs[0];
            assert.equal(log.event, 'LOG_SWAP');
            // 2.758274824473420261

            const actual = fromWei(log.args[3]);
            const relDif = calcRelativeDiff(expected, actual);
            if (verbose) {
                console.log('swapExactAmountOut');
                console.log(`expected: ${expected})`);
                console.log(`actual: ${actual})`);
                console.log(`relDif: ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('Fails joins exits with limits', async () => {
            await truffleAssert.reverts(
                pool.joinPool(toWei('10'), [toWei('1'), toWei('1'), toWei('1')]), 'ERR_LIMIT_IN',
            );

            await truffleAssert.reverts(
                pool.exitPool(toWei('10'), [toWei('10'), toWei('10'), toWei('10')]), 'ERR_LIMIT_OUT',
            );

            await truffleAssert.reverts(
                pool.joinswapExternAmountIn(DAI, toWei('100'), toWei('10')), 'ERR_LIMIT_OUT',
            );

            await truffleAssert.reverts(
                pool.exitswapPoolAmountIn(DAI, toWei('1'), toWei('1000')), 'ERR_LIMIT_OUT',
            );
        });

        it('Fails calling any swap on unbound token', async () => {
            await truffleAssert.reverts(
                pool.swapExactAmountIn(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountIn(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(XXX, toWei('2.5'), DAI, toWei('475'), toWei('200')), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.swapExactAmountOut(DAI, toWei('2.5'), XXX, toWei('475'), toWei('200')), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.joinswapExternAmountIn(XXX, toWei('2.5'), toWei('0')), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.exitswapPoolAmountIn(XXX, toWei('2.5'), toWei('0')), 'ERR_NOT_BOUND',
            );
        });

        it('Fails calling weights, balances, spot prices on unbound token', async () => {
            await truffleAssert.reverts(
                pool.getDenormalizedWeight(XXX), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getNormalizedWeight(XXX), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getBalance(XXX), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getSpotPrice(DAI, XXX), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getSpotPrice(XXX, DAI), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceSansFee(DAI, XXX), 'ERR_NOT_BOUND',
            );
            await truffleAssert.reverts(
                pool.getSpotPriceSansFee(XXX, DAI), 'ERR_NOT_BOUND',
            );
        });
    });

    describe('XPToken interactions', () => {
        it('Token descriptors', async () => {
            const name = await pool.name();
            assert.equal(name, 'XDeFi Pool Token');

            const symbol = await pool.symbol();
            assert.equal(symbol, 'XPT');

            const decimals = await pool.decimals();
            assert.equal(decimals, 18);
        });

        it('Token allowances', async () => {
            await pool.approve(user1, toWei('50'));
            let allowance = await pool.allowance(admin, user1);
            assert.equal(fromWei(allowance), 50);
        });

        it('Token transfers', async () => {
            await truffleAssert.reverts(
                pool.transferFrom(user2, admin, toWei('10')), 'ERR_BTOKEN_BAD_CALLER',
            );

            await pool.transferFrom(admin, user2, toWei('1'));
            await pool.approve(user2, toWei('10'));
            await pool.transferFrom(admin, user2, toWei('1'), { from: user2 });
        });
    });
});
