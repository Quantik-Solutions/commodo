pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";


contract Bank is Ownable {

  // address _collateralToken;
  uint256 _collateralTokenPrice;
  uint256 _collateralReserveBalance;

  // address _debtToken;
  uint256 _debtTokenPrice;
  uint256 _debtReserveBalance;

  uint256 _interestRate;
  uint256 _originationFee;
  uint256 _collateralizationRatio;
  uint256 _liquidationPenalty;

  uint256 _period = 86400; // One day

  struct Vault {
    uint256 collateralAmount;
    uint256 debtAmount;
    uint256 createdAt;
  }

  mapping (address => Vault) public vaults;

  constructor(
    // address collateralToken,
    // address debtToken,
    uint256 interestRate,
    uint256 originationFee,
    uint256 collateralizationRatio,
    uint256 liquidationPenalty) public {

    // _collateralToken = collateralToken
    // _debtToken = debtToken
    _interestRate = interestRate;
    _originationFee = originationFee;
    _collateralizationRatio = collateralizationRatio;
    _liquidationPenalty = liquidationPenalty;

    // TODO: Get price from oracle
    _debtTokenPrice = 1;
    _collateralTokenPrice = 1;
  }

  /////////////////////
  // RESERVE MANAGEMENT
  /////////////////////

  function getReserveBalance() public view returns (uint256) {
    return _debtReserveBalance;
  }

  function getReserveCollateralBalance() public view returns (uint256) {
    return _collateralReserveBalance;
  }

  function getInterestRate() public view returns (uint256) {
    return _interestRate;
  }

  function getOriginationFee() public view returns (uint256) {
    return _originationFee;
  }

  function getCollateralizationRatio() public view returns (uint256) {
    return _collateralizationRatio;
  }

  function getLiquidationPenalty() public view returns (uint256) {
    return _liquidationPenalty;
  }

  function reserveDeposit(uint256 amount) public onlyOwner {
    // NOTE: Assumes amount has been approved
    // IERC20(_debtToken).transferFrom(msg.sender, this, amount);
    _debtReserveBalance += amount;
  }

  function reserveWithdraw(uint256 amount) public onlyOwner {
    require(_debtReserveBalance >= amount, "NOT ENOUGH DEBT TOKENS IN RESERVE");
    // IERC20(_debtToken).transfer(msg.sender, amount);
    _debtReserveBalance -= amount;
  }

  function reserveWithdrawCollateral(uint256 amount) public onlyOwner {
    require(_collateralReserveBalance >= amount, "NOT ENOUGH COLLATERAL IN RESERVE");
    // IERC20(_collateralToken).transfer(msg.sender, amount);
    _collateralReserveBalance -= amount;
  }

  function updatePrice(uint256 debtTokenPrice, uint256 collateralTokenPrice) public onlyOwner {
    // TODO: Integrate with Tellor Oracle
    _debtTokenPrice = debtTokenPrice;
    _collateralTokenPrice = collateralTokenPrice;
  }

  function liquidate(address vaultOwner) public onlyOwner {
    // Require undercollateralization
    require(_getVaultCollateralizationRatio(vaultOwner) < _collateralizationRatio * 100, "VAULT NOT UNDERCOLLATERALIZED");
    _collateralReserveBalance += vaults[vaultOwner].collateralAmount;
    vaults[vaultOwner].collateralAmount = 0;
    vaults[vaultOwner].debtAmount = 0;
  }

  /////////////////////
  // VAULT MANAGEMENT
  /////////////////////

  function getVaultCollateralAmount() public view returns (uint256) {
    return vaults[msg.sender].collateralAmount;
  }

  function getVaultDebtAmount() public view returns (uint256) {
    return vaults[msg.sender].debtAmount;
  }

  function vaultDeposit(uint256 amount) public {
    // NOTE: Assumes amount has been approved
    require(vaults[msg.sender].collateralAmount == 0, "ALREADY DEPOSITED COLLATERAL");
    // IERC20(_collateralToken).transferFrom(msg.sender, this, amount);
    vaults[msg.sender].collateralAmount += amount;
  }

  function vaultBorrow(uint256 amount) public {
    require(vaults[msg.sender].debtAmount == 0, "ALREADY BORROWING");
    require(vaults[msg.sender].collateralAmount != 0, "NO COLLATERAL");
    uint256 maxBorrow = vaults[msg.sender].collateralAmount * _collateralTokenPrice / _debtTokenPrice / _collateralizationRatio * 100;
    require(amount < maxBorrow, "NOT ENOUGH COLLATERAL");
    require(amount <= _debtReserveBalance, "NOT ENOUGH RESERVES");
    vaults[msg.sender].debtAmount += amount + ((amount * _originationFee) / 100);
    _debtReserveBalance -= amount;
    vaults[msg.sender].createdAt = block.timestamp;
    // IERC20(_debtToken).transfer(msg.sender, amount);
  }

  function vaultRepay(uint256 amount) public {
    // Update debtAmount
    vaults[msg.sender].debtAmount = getVaultRepayAmount();
    // Subtract amount from debtAmount
    require(amount <= vaults[msg.sender].debtAmount, "CANNOT REPAY MORE THAN OWED");
    // IERC20(_debtToken).transferFrom(msg.sender, this, amount);
    vaults[msg.sender].debtAmount -= amount;
    _debtReserveBalance += amount;
    // Reset createdAt for this vault to start recalculating interest with new debtAmount
    vaults[msg.sender].createdAt = block.timestamp;
  }

  function vaultWithdraw() public {
    require(vaults[msg.sender].debtAmount == 0, "DEBT OWED");
    // IERC20(_collateralToken).transfer(msg.sender, vaults[msg.sender].collateralAmount);
    vaults[msg.sender].collateralAmount = 0;
  }

  function getVaultRepayAmount() public view returns (uint256) {
    uint256 currentPeriod = block.timestamp / _period;
    uint256 principal = vaults[msg.sender].debtAmount;
    for (uint256 i = vaults[msg.sender].createdAt / _period; i < currentPeriod; i++)
      principal += principal * _interestRate / 100 / 365;
    return principal;
  }

  function getVaultCollateralizationRatio() public view returns (uint256) {
    return _getVaultCollateralizationRatio(msg.sender);
  }

  function _getVaultCollateralizationRatio(address vaultOwner) private view returns (uint256) {
    return _percent(vaults[vaultOwner].collateralAmount * _collateralTokenPrice,
                    vaults[vaultOwner].debtAmount * _debtTokenPrice,
                    4);
  }

  function _percent(uint numerator, uint denominator, uint precision) private pure returns(uint quotient) {
        uint _numerator  = numerator * 10 ** (precision+1);
        uint _quotient =  ((_numerator / denominator) + 5) / 10;
        return ( _quotient);
  }



}
