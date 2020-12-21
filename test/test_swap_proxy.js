const Decimal = require('decimal.js');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');
const { address } = require('./utils/Ethereum');
const XSwapProxy = artifacts.require('XSwapProxyV1');
const TToken = artifacts.require('TToken');
const TTokenFactory = artifacts.require('TTokenFactory');
const XFactory = artifacts.require('XFactory');
const XPool = artifacts.require('XPool');
const Weth9 = artifacts.require('WETH9');
const errorDelta = 10 ** -8;
//const verbose = process.env.VERBOSE;
const verbose = true;

contract('XSwapProxy', async (accounts) => {
    const admin = accounts[0];
    const nonAdmin = accounts[1];
    const minter = accounts[2];
    const { toWei } = web3.utils;
    const { fromWei } = web3.utils;

    const MAX = web3.utils.toTwosComplement(-1);

    describe('Batch Swaps', () => {
        let factory;
        let proxy; let PROXY;
        let tokens;
        let pool1; let pool2; let pool3;
        let POOL1; let POOL2; let POOL3;
        let weth; let dai; let mkr;
        let WETH; let DAI; let MKR;

        before(async () => {
            weth = await Weth9.deployed();
            WETH = weth.address;

            proxy = await XSwapProxy.deployed();
            PROXY = proxy.address;
            tokens = await TTokenFactory.deployed();
            factory = await XFactory.deployed();

            await tokens.build('DAI', 'DAI', 18, minter, { from: minter });
            await tokens.build('MKR', 'MKR', 18, minter, { from: minter });

            DAI = await tokens.get.call('DAI');
            MKR = await tokens.get.call('MKR');

            dai = await TToken.at(DAI);
            mkr = await TToken.at(MKR);

            let name = await dai.name();
            let symbol = await dai.symbol();
            console.log(`DAI: ${DAI}, name:, ${name}, symbol: ${symbol}`);

            let weth_balance_admin = await weth.balanceOf(admin);
            let dai_balance_admin = await dai.balanceOf(admin);
            let weth_balance_nonadmin = await weth.balanceOf(nonAdmin);
            let dai_balance_nonadmin = await dai.balanceOf(nonAdmin);
            console.log(`weth_balance_admin: ${weth_balance_admin}, dai_balance_adminL: ${dai_balance_admin},  weth_balance_nonadmin: ${weth_balance_nonadmin}, dai_balance_nonadmin: ${dai_balance_nonadmin}`);

            await weth.deposit({ from: admin, value: toWei('25') });
            await dai.mint(admin, toWei('10000'), { from: minter });
            await mkr.mint(admin, toWei('20'), { from: minter });

            await weth.deposit({ from: nonAdmin, value: toWei('25') });
            await dai.mint(nonAdmin, toWei('10000'), { from: minter });
            await mkr.mint(nonAdmin, toWei('20'), { from: minter });

            POOL1 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool1 = await XPool.at(POOL1);

            POOL2 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool2 = await XPool.at(POOL2);

            POOL3 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool3 = await XPool.at(POOL3);

            await weth.approve(PROXY, MAX, { from: nonAdmin });
            await dai.approve(PROXY, MAX, { from: nonAdmin });
            await mkr.approve(PROXY, MAX, { from: nonAdmin });

            await weth.approve(POOL1, MAX);
            await dai.approve(POOL1, MAX);
            await mkr.approve(POOL1, MAX);

            await weth.approve(POOL2, MAX);
            await dai.approve(POOL2, MAX);
            await mkr.approve(POOL2, MAX);

            await weth.approve(POOL3, MAX);
            await dai.approve(POOL3, MAX);
            await mkr.approve(POOL3, MAX);

            await pool1.bind(WETH, toWei('6'), toWei('5'));
            await pool1.bind(DAI, toWei('1200'), toWei('5'));
            await pool1.bind(MKR, toWei('2'), toWei('5'));
            await pool1.finalize();

            await pool2.bind(WETH, toWei('2'), toWei('10'));
            await pool2.bind(DAI, toWei('800'), toWei('20'));
            await pool2.finalize();

            await pool3.bind(WETH, toWei('15'), toWei('5'));
            await pool3.bind(DAI, toWei('2500'), toWei('5'));
            await pool3.bind(MKR, toWei('5'), toWei('5'));
            await pool3.finalize();
        });

        it('batchSwapExactIn dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('1'),
                    toWei('0'),
                    MAX,
                ],
            ];
            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountOut = await proxy.batchSwapExactIn.call(
                swaps, WETH, DAI, toWei('2'), toWei('0'), address(0),
                { from: nonAdmin },
            );

            const pool1Out = calcOutGivenIn(6, 5, 1200, 5, 0.5, swapFee);
            const pool2Out = calcOutGivenIn(2, 10, 800, 20, 0.5, swapFee);
            const pool3Out = calcOutGivenIn(15, 5, 2500, 5, 1, swapFee);

            const expectedTotalOut = pool1Out.plus(pool2Out).plus(pool3Out);

            const relDif = calcRelativeDiff(expectedTotalOut, Decimal(fromWei(totalAmountOut)));

            if (verbose) {
                console.log('batchSwapExactIn');
                console.log(`expected: ${expectedTotalOut})`);
                console.log(`actual  : ${fromWei(totalAmountOut)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchSwapExactOut dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('5'),
                    toWei('500'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountIn = await proxy.batchSwapExactOut.call(
                swaps, WETH, DAI, toWei('7'), address(0),
                { from: nonAdmin },
            );

            const pool1In = calcInGivenOut(6, 5, 1200, 5, 100, swapFee);
            const pool2In = calcInGivenOut(2, 10, 800, 20, 100, swapFee);
            const pool3In = calcInGivenOut(15, 5, 2500, 5, 500, swapFee);

            const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

            const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
            if (verbose) {
                console.log('batchSwapExactOut');
                console.log(`expected: ${expectedTotalIn})`);
                console.log(`actual  : ${fromWei(totalAmountIn)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchEthInSwapExactIn dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('0.5'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('1'),
                    toWei('0'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountOut = await proxy.batchEthInSwapExactIn.call(
                swaps, DAI, toWei('0'), address(0),
                { from: nonAdmin, value: toWei('2') },
            );

            const pool1Out = calcOutGivenIn(6, 5, 1200, 5, 0.5, swapFee);
            const pool2Out = calcOutGivenIn(2, 10, 800, 20, 0.5, swapFee);
            const pool3Out = calcOutGivenIn(15, 5, 2500, 5, 1, swapFee);

            const expectedTotalOut = pool1Out.plus(pool2Out).plus(pool3Out);

            const relDif = calcRelativeDiff(expectedTotalOut, Decimal(fromWei(totalAmountOut)));
            if (verbose) {
                console.log('batchEthInSwapExactIn');
                console.log(`expected: ${expectedTotalOut})`);
                console.log(`actual  : ${fromWei(totalAmountOut)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchEthOutSwapExactIn dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('30'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('45'),
                    toWei('0'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('75'),
                    toWei('0'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountOut = await proxy.batchEthOutSwapExactIn.call(
                swaps, DAI, toWei('150'), toWei('0.5'), address(0),
                { from: nonAdmin },
            );

            const pool1Out = calcOutGivenIn(1200, 5, 6, 5, 30, swapFee);
            const pool2Out = calcOutGivenIn(800, 20, 2, 10, 45, swapFee);
            const pool3Out = calcOutGivenIn(2500, 5, 15, 5, 75, swapFee);

            const expectedTotalOut = pool1Out.plus(pool2Out).plus(pool3Out);

            const relDif = calcRelativeDiff(expectedTotalOut, Decimal(fromWei(totalAmountOut)));
            if (verbose) {
                console.log('batchEthOutSwapExactIn');
                console.log(`expected: ${expectedTotalOut})`);
                console.log(`actual  : ${fromWei(totalAmountOut)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchEthInSwapExactOut dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('1'),
                    toWei('100'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('5'),
                    toWei('500'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountIn = await proxy.batchEthInSwapExactOut.call(
                swaps, DAI, address(0),
                { from: nonAdmin, value: toWei('7.5') },
            );

            const pool1In = calcInGivenOut(6, 5, 1200, 5, 100, swapFee);
            const pool2In = calcInGivenOut(2, 10, 800, 20, 100, swapFee);
            const pool3In = calcInGivenOut(15, 5, 2500, 5, 500, swapFee);

            const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

            const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
            if (verbose) {
                console.log('batchEthInSwapExactOut');
                console.log(`expected: ${expectedTotalIn})`);
                console.log(`actual  : ${fromWei(totalAmountIn)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });

        it('batchEthOutSwapExactOut dry', async () => {
            const swaps = [
                [
                    POOL1,
                    toWei('150'),
                    toWei('0.5'),
                    MAX,
                ],
                [
                    POOL2,
                    toWei('150'),
                    toWei('0.5'),
                    MAX,
                ],
                [
                    POOL3,
                    toWei('550'),
                    toWei('2.5'),
                    MAX,
                ],
            ];

            const swapFee = fromWei(await pool1.getSwapFee());
            const totalAmountIn = await proxy.batchEthOutSwapExactOut.call(
                swaps, DAI, toWei('750'), address(0),
                { from: nonAdmin },
            );

            const pool1In = calcInGivenOut(1200, 5, 6, 5, 0.5, swapFee);
            const pool2In = calcInGivenOut(800, 20, 2, 10, 0.5, swapFee);
            const pool3In = calcInGivenOut(2500, 5, 15, 5, 2.5, swapFee);

            const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

            const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
            if (verbose) {
                console.log('batchEthOutSwapExactOut');
                console.log(`expected: ${expectedTotalIn})`);
                console.log(`actual  : ${fromWei(totalAmountIn)})`);
                console.log(`relDif  : ${relDif})`);
            }

            assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        });
    });
});
