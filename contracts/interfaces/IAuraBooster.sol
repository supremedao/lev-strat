// transaction example: https://etherscan.io/tx/0xb2d6067dfbde2eda99ae62b79d734b2943a78a06cba67ea63f48266b9a5f5138
// contract: https://etherscan.io/address/0xa57b8d98dae62b26ec3bcc4a365338157060b234

pragma solidity ^0.8.0;


contract IAuraBooster {
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);
    function depositAll(uint256 _pid, bool _stake) external returns(bool);
    function withdraw(uint256 _pid, uint256 _amount) external returns(bool);
    function withdrawAll(uint256 _pid) external returns(bool);
    function withdrawTo(uint256 _pid, uint256 _amount, address _to) external returns(bool);
}
