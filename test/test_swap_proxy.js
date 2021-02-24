const Decimal = require('decimal.js');
const { calcOutGivenIn, calcInGivenOut, calcRelativeDiff } = require('../lib/calc_comparisons');
const { address } = require('./utils/Ethereum');
const XSwapProxy = artifacts.require('XSwapProxyV1');
const TToken = artifacts.require('TToken');
const TTokenFactory = artifacts.require('TTokenFactory');
const XFactory = artifacts.require('XFactory');
const XPool = artifacts.require('XPool');
const XConfig = artifacts.require('XConfig');
const Weth9 = artifacts.require('WETH9');
const errorDelta = 10 ** -8;
const swapFee = 10 ** -1; // 0.001;
const { expectRevert } = require('@openzeppelin/test-helpers');

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
        let xconfig; let XCONFIG;
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

            xconfig = await XConfig.deployed();
            XCONFIG = xconfig.address;

            await tokens.build('DAI', 'DAI', 18, minter, { from: minter });
            await tokens.build('MKR', 'MKR', 18, minter, { from: minter });

            DAI = await tokens.get.call('DAI');
            MKR = await tokens.get.call('MKR');

            dai = await TToken.at(DAI);
            mkr = await TToken.at(MKR);

            await weth.deposit({ from: admin, value: toWei('30') });
            await dai.mint(admin, toWei('10000'), { from: minter });
            await mkr.mint(admin, toWei('20'), { from: minter });

            await weth.deposit({ from: nonAdmin, value: toWei('25') });
            await dai.mint(nonAdmin, toWei('10000'), { from: minter });
            await mkr.mint(nonAdmin, toWei('20'), { from: minter });

            let weth_balance_admin = await weth.balanceOf(admin);
            let dai_balance_admin = await dai.balanceOf(admin);
            let weth_balance_nonadmin = await weth.balanceOf(nonAdmin);
            let dai_balance_nonadmin = await dai.balanceOf(nonAdmin);
            //console.log(`weth_balance_admin: ${fromWei(weth_balance_admin)}, dai_balance_admin: ${fromWei(dai_balance_admin)},  weth_balance_nonadmin: ${fromWei(weth_balance_nonadmin)}, dai_balance_nonadmin: ${fromWei(dai_balance_nonadmin)}`)
            //weth_balance_admin: 30, dai_balance_admin: 10000, weth_balance_nonadmin: 25, dai_balance_nonadmin: 10000

            POOL1 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool1 = await XPool.at(POOL1);

            POOL2 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool2 = await XPool.at(POOL2);

            POOL3 = await factory.newXPool.call(); // this works fine in clean room
            await factory.newXPool();
            pool3 = await XPool.at(POOL3);

            await weth.approve(PROXY, MAX);
            await dai.approve(PROXY, MAX);
            await mkr.approve(PROXY, MAX);

            await weth.approve(POOL1, MAX);
            await dai.approve(POOL1, MAX);
            await mkr.approve(POOL1, MAX);

            await weth.approve(POOL2, MAX);
            await dai.approve(POOL2, MAX);
            await mkr.approve(POOL2, MAX);

            await weth.approve(POOL3, MAX);
            await dai.approve(POOL3, MAX);
            await mkr.approve(POOL3, MAX);

            await weth.transfer(POOL1, toWei('6'));
            await pool1.bind(WETH, toWei('5'));
            await dai.transfer(POOL1, toWei('1200'));
            await pool1.bind(DAI, toWei('5'));
            await mkr.transfer(POOL1, toWei('2'));
            await pool1.bind(MKR, toWei('5'));
            await pool1.finalize(toWei(String(swapFee)));// 0.1%;

            await weth.transfer(POOL2, toWei('2'));
            await pool2.bind(WETH, toWei('10'));
            await dai.transfer(POOL2, toWei('800'));
            await pool2.bind(DAI, toWei('20'));
            await pool2.finalize(toWei(String(swapFee)));// 0.1%;

            await weth.transfer(POOL3, toWei('15'));
            await pool3.bind(WETH, toWei('5'));
            await dai.transfer(POOL3, toWei('2500'));
            await pool3.bind(DAI, toWei('5'));
            await mkr.transfer(POOL3, toWei('5'));
            await pool3.bind(MKR, toWei('5'));
            await pool3.finalize(toWei(String(swapFee)));// 0.1%;

            weth_balance_admin = await weth.balanceOf(admin);
            dai_balance_admin = await dai.balanceOf(admin);
            weth_balance_nonadmin = await weth.balanceOf(nonAdmin);
            dai_balance_nonadmin = await dai.balanceOf(nonAdmin);
            //console.log(`weth_balance_admin: ${fromWei(weth_balance_admin)}, dai_balance_admin: ${fromWei(dai_balance_admin)},  weth_balance_nonadmin: ${fromWei(weth_balance_nonadmin)}, dai_balance_nonadmin: ${fromWei(dai_balance_nonadmin)}`)
            //weth_balance_admin: 7, dai_balance_admin: 5500, weth_balance_nonadmin: 25, dai_balance_nonadmin: 10000
            assert.equal(weth_balance_admin, toWei('7'));
            assert.equal(weth_balance_nonadmin, toWei('25'));
            assert.equal(dai_balance_admin, toWei('5500'));
            assert.equal(dai_balance_nonadmin, toWei('10000'));
        });

        it('deploy duplicated pool should not work', async () => {
            const createTokens = [];
            const createBalances = [];
            const createWeights = [toWei('5'), toWei('5')];
            const swapFee = toWei('0.025');
            const exitFee = 0;

            if (DAI <= MKR) {
                createTokens.push(DAI);
                createBalances.push(toWei('10'));
                createTokens.push(MKR);
                createBalances.push(toWei('1'));
            } else {
                createTokens.push(MKR);
                createBalances.push(toWei('1'));
                createTokens.push(DAI);
                createBalances.push(toWei('10'));
            }

            let swproxy = await xconfig.getSwapProxy();
            assert.equal(swproxy, PROXY);

            let poolSigCount = (await xconfig.poolSigCount.call()).toString();
            assert.equal(poolSigCount, '0');

            //should success
            let pool = await proxy.create(XFactory.address, createTokens, createBalances, createWeights, swapFee, exitFee);

            const createNewWeights = [toWei('15'), toWei('15')];
            //should revert
            await expectRevert(
                proxy.create(XFactory.address, createTokens, createBalances, createNewWeights, swapFee, exitFee),
                'ERR_POOL_EXISTS',
            );

            poolSigCount = (await xconfig.poolSigCount.call()).toString();
            assert.equal(poolSigCount, '1');

            //remove liquidity from pool
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
            const swapFee = fromWei(await pool1.swapFee());
            const totalAmountOut = await proxy.batchSwapExactIn.call(
                swaps, WETH, DAI, toWei('2'), toWei('0'),
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

            const swapFee = fromWei(await pool1.swapFee());
            const totalAmountIn = await proxy.batchSwapExactOut.call(
                swaps, WETH, DAI, toWei('7'),
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

            const swapFee = fromWei(await pool1.swapFee());
            const totalAmountOut = await proxy.batchEthInSwapExactIn.call(
                swaps, DAI, toWei('0'),
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

            const swapFee = fromWei(await pool1.swapFee());
            const totalAmountOut = await proxy.batchEthOutSwapExactIn.call(
                swaps, DAI, toWei('150'), toWei('0.5'),
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

        // it('batchEthInSwapExactOut dry', async () => {
        //     const swaps = [
        //         [
        //             POOL1,
        //             toWei('1'),
        //             toWei('100'),
        //             MAX,
        //         ],
        //         [
        //             POOL2,
        //             toWei('1'),
        //             toWei('100'),
        //             MAX,
        //         ],
        //         [
        //             POOL3,
        //             toWei('5'),
        //             toWei('500'),
        //             MAX,
        //         ],
        //     ];

        //     const swapFee = fromWei(await pool1.swapFee());
        //     const totalAmountIn = await proxy.batchEthInSwapExactOut.call(
        //         swaps, DAI,
        //         { from: nonAdmin, value: toWei('7.5') },
        //     );

        //     const pool1In = calcInGivenOut(6, 5, 1200, 5, 100, swapFee);
        //     const pool2In = calcInGivenOut(2, 10, 800, 20, 100, swapFee);
        //     const pool3In = calcInGivenOut(15, 5, 2500, 5, 500, swapFee);

        //     const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

        //     const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
        //     if (verbose) {
        //         console.log('batchEthInSwapExactOut');
        //         console.log(`expected: ${expectedTotalIn})`);
        //         console.log(`actual  : ${fromWei(totalAmountIn)})`);
        //         console.log(`relDif  : ${relDif})`);
        //     }

        //     assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        // });

        // it('batchEthOutSwapExactOut dry', async () => {
        //     const swaps = [
        //         [
        //             POOL1,
        //             toWei('150'),
        //             toWei('0.5'),
        //             MAX,
        //         ],
        //         [
        //             POOL2,
        //             toWei('150'),
        //             toWei('0.5'),
        //             MAX,
        //         ],
        //         [
        //             POOL3,
        //             toWei('550'),
        //             toWei('2.5'),
        //             MAX,
        //         ],
        //     ];

        //     const swapFee = fromWei(await pool1.swapFee());
        //     const totalAmountIn = await proxy.batchEthOutSwapExactOut.call(
        //         swaps, DAI, toWei('750'),
        //         { from: nonAdmin },
        //     );

        //     const pool1In = calcInGivenOut(1200, 5, 6, 5, 0.5, swapFee);
        //     const pool2In = calcInGivenOut(800, 20, 2, 10, 0.5, swapFee);
        //     const pool3In = calcInGivenOut(2500, 5, 15, 5, 2.5, swapFee);

        //     const expectedTotalIn = pool1In.plus(pool2In).plus(pool3In);

        //     const relDif = calcRelativeDiff(expectedTotalIn, Decimal(fromWei(totalAmountIn)));
        //     if (verbose) {
        //         console.log('batchEthOutSwapExactOut');
        //         console.log(`expected: ${expectedTotalIn})`);
        //         console.log(`actual  : ${fromWei(totalAmountIn)})`);
        //         console.log(`relDif  : ${relDif})`);
        //     }

        //     assert.isAtMost(relDif.toNumber(), (errorDelta * swaps.length));
        // });
    });
});
