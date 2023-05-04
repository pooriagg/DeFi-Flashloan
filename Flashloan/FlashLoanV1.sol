//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface IFlashLoanReceiver {
    function execute() external;
}

interface IERC20 {
    function transfer(address _to, uint256 _amount) external returns(bool);
    function balanceOf(address _account) external view returns(uint256);
    function decimals() external view returns(uint8);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract FlashLoanV1 {

    IERC20 public immutable USDC;
    uint8 public fee;
    address public immutable poolOwner;

    uint256 private totalFeeEarned;

    event FlashLoanExecuted(address indexed _receiver, uint256 indexed _amount, uint256 _feePaied, uint256 indexed _time);

    constructor(address _usdc, uint8 _fee) {
        require(_fee < 100, "Invalid fee percent");
        require(_usdc != address(0), "Invalid token address");

        USDC = IERC20(_usdc);
        fee = _fee;
        poolOwner = msg.sender;
    }

    modifier onlyPoolOwner() {
        require(msg.sender == poolOwner, "Only pool owner");
        _;
    }

    bool lock;
    modifier locker() {
        require(lock == false, "Locked");
        lock = true;
        _;
        lock = false;
    }

    function getPoolFee() external view returns(uint8) {
        return fee;
    }

    function flashloanExecution(uint _usdcAmount /*, bytes calldata _data */) external locker {
        uint poolBalanceBefore = USDC.balanceOf(address(this));
        require(_usdcAmount <= poolBalanceBefore, "Pool insufficient balance.");

        bool res = USDC.transfer(msg.sender, _usdcAmount);
        require(res == true, "Failed to send usdc tokens.");
        IFlashLoanReceiver(msg.sender).execute();
        // OR
        /*
        (bool response,) = (msg.sender).call(_data);
        require(response, "External call failed");
        */

        uint poolBalanceAfter = USDC.balanceOf(address(this));
        uint feeAmount = (_usdcAmount * fee) / 100;
        uint expectedPoolBalance = poolBalanceBefore + feeAmount;
        require(poolBalanceAfter == expectedPoolBalance, "Flashloan + fees, didn't paid back compeletely.");
        
        totalFeeEarned += feeAmount;

        emit FlashLoanExecuted({
            _receiver: msg.sender,
            _amount: _usdcAmount,
            _time: block.timestamp,
	    _feePaied: feeAmount
        });
    }

    function updateFee(uint8 _newFee) external onlyPoolOwner {
        require(_newFee < 100, "Invalid fee percent");

        fee = _newFee;
    }

    function increasePoolBalance(uint256 _amount) external onlyPoolOwner locker {
        require(_amount != 0, "Invalid token amount.");
        require(USDC.allowance(poolOwner, address(this)) >= _amount, "Insufficient usdc allowance.");

        try USDC.transferFrom(poolOwner, address(this), _amount) returns(bool res) {
            require(res == true, "Transfering  usdc failed.");
        } catch {  
            revert("External call failed.");
        }
    }

    function transferFees(address _feeReceiver, uint256 _amount) external onlyPoolOwner locker {
        require(_feeReceiver != address(0) && _amount != 0, "Invalid data received.");
        require(_amount <= totalFeeEarned, "Insufficient fee amount.");

        totalFeeEarned -= _amount;

        try USDC.transfer(poolOwner, _amount) returns(bool res) {
            require(res == true, "Transfering fees failed.");
        } catch {  
            revert("External call failed.");
        }
    }

    function decreasePoolBalance(uint256 _amount) external onlyPoolOwner locker {
        require(_amount != 0, "Invalid token amount.");
        require(_amount <= (USDC.balanceOf(address(this)) - totalFeeEarned), "Invalid amount requested.");

        try USDC.transfer(poolOwner, _amount) returns(bool res) {
            require(res == true, "Transfering funds failed.");
        } catch {  
            revert("External call failed.");
        }
    }

    function getAllFees() external view returns(uint256) {
        return totalFeeEarned;
    }

    function getUsdcReserve() external view returns(uint256) {
        return USDC.balanceOf(address(this));
    }

}
