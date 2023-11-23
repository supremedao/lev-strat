// https://etherscan.io/address/0x100daa78fc509db39ef7d04de0c1abd299f4c6ce#code

pragma solidity ^0.8.0;

// ChatGPT generated interface
interface IcrvUSDController {
    function debt(address user) external view returns (uint256);
    function loan_exists(address user) external view returns (bool);
    function total_debt() external view returns (uint256);
    function max_borrowable(uint256 collateral, uint256 N) external view returns (uint256);
    function min_collateral(uint256 debt, uint256 N) external view returns (uint256);
    function calculate_debt_n1(uint256 collateral, uint256 debt, uint256 N) external view returns (int256);
    function create_loan(uint256 collateral, uint256 debt, uint256 N) external payable;
    function create_loan_extended(
        uint256 collateral,
        uint256 debt,
        uint256 N,
        address callbacker,
        uint256[5] calldata callback_args
    ) external payable;
    function add_collateral(uint256 collateral, address _for) external payable;
    function remove_collateral(uint256 collateral, bool use_eth) external;
    function borrow_more(uint256 collateral, uint256 debt) external payable;
    function repay(uint256 _d_debt) external payable;
    function health(address user, bool full) external view returns (int256);
    function amm_price() external view returns (uint256);
    function user_prices(address user) external view returns (uint256[2] memory);
    function user_state(address user) external view returns (uint256[4] memory);
}
