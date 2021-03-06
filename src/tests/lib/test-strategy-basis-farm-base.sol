pragma solidity ^0.6.7;

import "../lib/hevm.sol";
import "../lib/user.sol";
import "../lib/test-approx.sol";
import "../lib/test-defi-base.sol";

import "../../interfaces/strategy.sol";
import "../../interfaces/curve.sol";
import "../../interfaces/uniswapv2.sol";

import "../../pickle-jar.sol";
import "../../controller-v4.sol";

contract StrategyBasisFarmTestBase is DSTestDefiBase {
    address want;
    address token1;

    address governance;
    address strategist;
    address timelock;

    address devfund;
    address treasury;

    PickleJar pickleJar;
    ControllerV4 controller;
    IStrategy strategy;

    function _getWant(uint256 daiAmount, uint256 amount) internal {
        address[] memory path = new address[](3);
        path[0] = weth;
        path[1] = dai;
        path[2] = token1;

        _getERC20(dai, daiAmount);
        _getERC20WithPath(token1, amount, path);

        uint256 _dai = IERC20(dai).balanceOf(address(this));
        uint256 _token1 = IERC20(token1).balanceOf(address(this));

        IERC20(dai).safeApprove(address(univ2), 0);
        IERC20(dai).safeApprove(address(univ2), _dai);

        IERC20(token1).safeApprove(address(univ2), 0);
        IERC20(token1).safeApprove(address(univ2), _token1);

        univ2.addLiquidity(
            dai,
            token1,
            _dai,
            _token1,
            0,
            0,
            address(this),
            now + 60
        );
    }

    // **** Tests ****

    function _test_timelock() internal {
        assertTrue(strategy.timelock() == timelock);
        strategy.setTimelock(address(1));
        assertTrue(strategy.timelock() == address(1));
    }

    function _test_withdraw_release() internal {
        uint256 decimals = ERC20(token1).decimals();
        _getWant(10 ether, 10 ether);
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).safeApprove(address(pickleJar), 0);
        IERC20(want).safeApprove(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();
        hevm.warp(block.timestamp + 1 weeks);
        strategy.harvest();

        // Checking withdraw
        uint256 _before = IERC20(want).balanceOf(address(pickleJar));
        controller.withdrawAll(want);
        uint256 _after = IERC20(want).balanceOf(address(pickleJar));
        assertTrue(_after > _before);
        _before = IERC20(want).balanceOf(address(this));
        pickleJar.withdrawAll();
        _after = IERC20(want).balanceOf(address(this));
        assertTrue(_after > _before);

        // Check if we gained interest
        assertTrue(_after > _want);
    }

    function _test_get_earn_harvest_rewards() internal {
        uint256 decimals = ERC20(token1).decimals();
        _getWant(10 ether, 4000 * (10**decimals));
        uint256 _want = IERC20(want).balanceOf(address(this));
        IERC20(want).safeApprove(address(pickleJar), 0);
        IERC20(want).safeApprove(address(pickleJar), _want);
        pickleJar.deposit(_want);
        pickleJar.earn();
        hevm.warp(block.timestamp + 1 weeks);

        // Call the harvest function
        uint256 _before = pickleJar.balance();
        uint256 _treasuryBefore = IERC20(want).balanceOf(treasury);
        strategy.harvest();
        uint256 _after = pickleJar.balance();
        uint256 _treasuryAfter = IERC20(want).balanceOf(treasury);

        uint256 earned = _after.sub(_before).mul(1000).div(800);
        uint256 earnedRewards = earned.mul(200).div(1000); // 20%
        uint256 actualRewardsEarned = _treasuryAfter.sub(_treasuryBefore);

        // 20% performance fee is given
        assertEqApprox(earnedRewards, actualRewardsEarned);

        // Withdraw
        uint256 _devBefore = IERC20(want).balanceOf(devfund);
        _treasuryBefore = IERC20(want).balanceOf(treasury);
        uint256 _stratBal = strategy.balanceOf();
        pickleJar.withdrawAll();
        uint256 _devAfter = IERC20(want).balanceOf(devfund);
        _treasuryAfter = IERC20(want).balanceOf(treasury);

        // 0% goes to dev
        uint256 _devFund = _devAfter.sub(_devBefore);
        assertEq(_devFund, 0);

        // 0% goes to treasury
        uint256 _treasuryFund = _treasuryAfter.sub(_treasuryBefore);
        assertEq(_treasuryFund, 0);
    }
}
