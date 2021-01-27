const Decimal = require('decimal.js');
const truffleAssert = require('truffle-assertions');
const { calcRelativeDiff } = require('../lib/calc_comparisons');
const { address } = require('./utils/Ethereum');
const XPool = artifacts.require('XPool');
const XFactory = artifacts.require('XFactory');
const TToken = artifacts.require('TToken');
const errorDelta = 10 ** -8;
const swapFee = 0.001; // 0.001;
const exitFee = 0;
const verbose = process.env.VERBOSE;


contract('XPool', async (accounts) => {
    const admin = accounts[0];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;
    const MAX = web3.utils.toTwosComplement(-1);

    let WETH; let DAI;
    let weth; let dai;
    let factory; // XPool factory
    let pool; // first pool w/ defaults
    let POOL; //   pool address

    const wethBalance = '1000';
    const wethDenorm = '1';

    let currentWethBalance = Decimal(wethBalance);
    let previousWethBalance = currentWethBalance;

    const daiBalance = '1000';
    const daiDenorm = '49';

    let currentDaiBalance = Decimal(daiBalance);
    let previousDaiBalance = currentDaiBalance;

    let currentPoolBalance = Decimal(0);
    let previousPoolBalance = Decimal(0);

    const sumWeights = Decimal(wethDenorm).add(Decimal(daiDenorm));
    const wethNorm = Decimal(wethDenorm).div(Decimal(sumWeights));
    const daiNorm = Decimal(daiDenorm).div(Decimal(sumWeights));

    async function logAndAssertCurrentBalances() {
        let expected = currentPoolBalance;
        let actual = await pool.totalSupply();
        actual = Decimal(fromWei(actual));
        let relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('Pool Balance');
            console.log(`expected: ${expected})`);
            console.log(`actual  : ${actual})`);
            console.log(`relDif  : ${relDif})`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);

        expected = currentWethBalance;
        actual = await pool.getBalance(WETH);
        actual = Decimal(fromWei(actual));
        relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('WETH Balance');
            console.log(`expected: ${expected})`);
            console.log(`actual  : ${actual})`);
            console.log(`relDif  : ${relDif})`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);

        expected = currentDaiBalance;
        actual = await pool.getBalance(DAI);
        actual = Decimal(fromWei(actual));
        relDif = calcRelativeDiff(expected, actual);
        if (verbose) {
            console.log('Dai Balance');
            console.log(`expected: ${expected})`);
            console.log(`actual  : ${actual})`);
            console.log(`relDif  : ${relDif})`);
        }

        assert.isAtMost(relDif.toNumber(), errorDelta);
    }

    before(async () => {
        factory = await XFactory.deployed();

        POOL = await factory.newXPool.call(); // this works fine in clean room
        await factory.newXPool();
        pool = await XPool.at(POOL);

        weth = await TToken.new('Wrapped Ether', 'WETH', 18, admin);
        dai = await TToken.new('Dai Stablecoin', 'DAI', 18, admin);

        WETH = weth.address;
        DAI = dai.address;

        await weth.mint(admin, MAX);
        await dai.mint(admin, MAX);

        await weth.approve(POOL, MAX);
        await dai.approve(POOL, MAX);

        await weth.transfer(POOL, toWei(wethBalance));
        await pool.bind(WETH, toWei(wethDenorm));

        await dai.transfer(POOL, toWei(daiBalance));
        await pool.bind(DAI, toWei(daiDenorm));

        await pool.finalize(toWei(String(swapFee)));// 0.1%;
    });

    describe('Extreme weights', () => {
        it('swapExactAmountIn', async () => {
            const tokenIn = WETH;
            const tokenInAmount = toWei('500');
            const tokenOut = DAI;
            const minAmountOut = toWei('0');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountInRefer.call(
                tokenIn, tokenInAmount, tokenOut, minAmountOut, maxPrice, address(0)
            );

            // Checking outputs
            let expected = Decimal('8.23390841016124456');
            let actual = Decimal(fromWei(output.tokenAmountOut));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('74.1844011380065814');
            actual = Decimal(fromWei(output.spotPriceAfter));
            relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[1]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });


        it('swapExactAmountOut', async () => {
            const tokenIn = WETH;
            const maxAmountIn = MAX;
            const tokenOut = DAI;
            const tokenAmountOut = toWei('333.333333333333333333');
            const maxPrice = MAX;

            const output = await pool.swapExactAmountOutRefer.call(
                tokenIn, maxAmountIn, tokenOut, tokenAmountOut, maxPrice, address(0)
            );

            // Checking outputs
            let expected = Decimal('425506505648.348073');
            let actual = Decimal(fromWei(output.tokenAmountIn));
            let relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[0]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);

            expected = Decimal('31306034272.9265099');
            actual = Decimal(fromWei(output.spotPriceAfter));
            relDif = calcRelativeDiff(expected, actual);

            if (verbose) {
                console.log('output[1]');
                console.log(`expected: ${expected})`);
                console.log(`actual  : ${actual})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), errorDelta);
        });

        it('joinPool', async () => {
            currentPoolBalance = '100';

            // // Call function
            const poolAmountOut = '1';
            await pool.joinPool(toWei(poolAmountOut), [MAX, MAX]);

            // // Update balance states
            previousPoolBalance = Decimal(currentPoolBalance);
            currentPoolBalance = Decimal(currentPoolBalance).add(Decimal(poolAmountOut));

            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.add(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (Decimal(poolAmountOut).div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.add(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });

        it('exitPool', async () => {
            // Call function
            // so that the balances of all tokens will go back exactly to what they were before joinPool()
            const poolAmountIn = 1 / (1 - exitFee);
            const poolAmountInAfterExitFee = Decimal(poolAmountIn).mul(Decimal(1).sub(exitFee));

            await pool.exitPool(toWei(String(poolAmountIn)), [toWei('0'), toWei('0')]);

            // Update balance states
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.sub(poolAmountInAfterExitFee);
            // Balances of all tokens increase proportionally to the pool balance
            previousWethBalance = currentWethBalance;
            let balanceChange = (poolAmountInAfterExitFee.div(previousPoolBalance)).mul(previousWethBalance);
            currentWethBalance = currentWethBalance.sub(balanceChange);
            previousDaiBalance = currentDaiBalance;
            balanceChange = (poolAmountInAfterExitFee.div(previousPoolBalance)).mul(previousDaiBalance);
            currentDaiBalance = currentDaiBalance.sub(balanceChange);

            // Print current balances after operation
            await logAndAssertCurrentBalances();
        });


        it('joinswapExternAmountIn', async () => {
            // Call function
            const tokenRatio = 1.1;
            // increase tbalance by 1.1 after swap fee
            const tokenAmountIn = (1 / (1 - swapFee * (1 - wethNorm))) * (currentWethBalance * (tokenRatio - 1));
            await pool.joinswapExternAmountIn(WETH, toWei(String(tokenAmountIn)), toWei('0'));
            // Update balance states
            previousWethBalance = currentWethBalance;
            currentWethBalance = currentWethBalance.add(Decimal(tokenAmountIn));
            previousPoolBalance = currentPoolBalance;
            currentPoolBalance = currentPoolBalance.mul(Decimal(tokenRatio).pow(wethNorm)); // increase by 1.1**wethNorm

            // Print current balances after operation
            //await logAndAssertCurrentBalances();
        });

        it('joinswapExternAmountIn should revert', async () => {
            // Call function
            const tokenRatio = 1.1;
            const tokenAmountIn = (1 / (1 - swapFee * (1 - wethNorm))) * (currentWethBalance * (tokenRatio));
            await truffleAssert.reverts(
                pool.joinswapExternAmountIn(WETH, toWei(String(tokenAmountIn)), toWei('0')),
                'ERR_MAX_IN_RATIO',
            );
        });

        it('exitswapPoolAmountIn should revert', async () => {
            // Call function
            const poolRatioAfterExitFee = 0.9;
            const poolAmountIn = currentPoolBalance * (1 - poolRatioAfterExitFee) * (1 / (1 - exitFee));
            await truffleAssert.reverts(
                pool.exitswapPoolAmountIn(WETH, toWei(String(poolAmountIn)), toWei('0')),
                'ERR_MAX_OUT_RATIO',
            );
        });
    });
});
