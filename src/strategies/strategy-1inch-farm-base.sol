// SPDX-License-Identifier: MIT
pragma solidity ^0.6.7;

import "./strategy-base.sol";
import "../interfaces/1inch-farm-lp.sol";
import "../interfaces/1inch-farm.sol";

abstract contract Strategy1inchFarmBase is StrategyBase {
    // Token addresses
    // oneinch is not using WETH, tokenA address for 1inch ETH/token1 pool is 0x0000000000000000000000000000000000000000
    // oneinch has farmingrewards pool per one 1inch-lp token

    address public constant oneinch = 0x111111111117dC0aa78b770fA6A738034120C302;

    //use this pool to swap 1inch to ETH (not weth), 1inch doens't use WETH
    address public constant oneinch_eth_pool = 0x0EF1B8a0E726Fc3948E15b23993015eB1627f210;

    //address public constant oneinchFactory = 0xbaf9a5d4b0052359326a6cdab54babaa3a3a9643;
    address public oneinchFarm;

    // ETH/<token1> pair
    address public token1;

    // How much 1inch tokens to keep?
    uint256 public keep1inch = 0;
    uint256 public constant keep1inchMax = 10000;


    constructor(
        address _token1,
        address _lp,
        address _pool,
        address _governance,
        address _strategist,
        address _controller,
        address _timelock
    )
        public
        StrategyBase(
            _lp,
            _governance,
            _strategist,
            _controller,
            _timelock
        )
    {
        oneinchFarm = _pool;
        token1 = _token1;
    }
    
    function balanceOfPool() public override view returns (uint256) {
        uint256 amount = IOneInchFarm(oneinchFarm).balanceOf(address(this));
        return amount;
    }

    function getHarvestable() external view returns (uint256) {
        return IOneInchFarm(oneinchFarm).earned(address(this));
    }

    // **** Setters ****

    function deposit() public override {
        uint256 _want = IERC20(want).balanceOf(address(this)); //want means 1inch lp token
        if (_want > 0) {
            IERC20(want).safeApprove(oneinchFarm, 0);
            IERC20(want).safeApprove(oneinchFarm, _want);
            IOneInchFarm(oneinchFarm).stake(_want);
        }
    }

    function _withdrawSome(uint256 _amount)
        internal
        override
        returns (uint256)
    {
        IOneInchFarm(oneinchFarm).withdraw(_amount);
        return _amount;
    }

    // **** Setters ****

    function setKeep1inch(uint256 _keep1inch) external {
        require(msg.sender == timelock, "!timelock");
        keep1inch = _keep1inch;
    }

    // **** State Mutations ****

    function harvest() public override onlyBenevolent {

        // Collects 1inch tokens
        IERC20(baseAsset).balanceOf(address(this));
        IOneInchFarm(oneinchFarm).getReward();
        uint256 _oneinch = IERC20(oneinch).balanceOf(address(this));

        if (_oneinch > 0) {
            // 10% is locked up for future gov
            uint256 _keep1inch = _oneinch.mul(keep1inch).div(keep1inchMax);
            IERC20(oneinch).safeTransfer(
                IController(controller).treasury(),
                _keep1inch
            );
            uint256 swapAmount = _oneinch.sub(_keep1inch);
            IERC20(oneinch).safeApprove(oneinch_eth_pool, 0);
            IERC20(oneinch).safeApprove(oneinch_eth_pool, swapAmount);
            IMooniswap(oneinch_eth_pool).swap(IERC20(oneinch), IERC20(address(0)), swapAmount, 0, address(0));
            //claim Opium functions here
        }

        // Swap half ETH for Token1 (e.g. Opium)
        uint256 _eth = address(this).balance;
        if (_eth > 0) {
            uint256 amount = _eth.div(2);
            IMooniswap(want).swap{value: amount}(IERC20(address(0)), IERC20(token1), amount, 0, address(0));
        }

        _eth = address(this).balance;
        uint256 _token1 = IERC20(token1).balanceOf(address(this));
        if (_eth > 0 && _token1 > 0) {
            //no need to approve ETH, it's not WETH

            IERC20(token1).safeApprove(want, 0);
            IERC20(token1).safeApprove(want, _token1);

            uint256[2] memory maxAmounts;
            uint256[2] memory minAmounts;
            maxAmounts[0] = _eth;
            maxAmounts[1] = _token1;
            minAmounts[0] = 0;
            minAmounts[1] = 0;

            IMooniswap(want).deposit{value: _eth}(maxAmounts, minAmounts);
        }

        // We want to get back 1inch LP tokens
        _distributePerformanceFeesAndDeposit();
    }
    receive() external payable {}
}
