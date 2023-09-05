// https://etherscan.io/address/0x95ecdc6caaf7e4805fcef2679a92338351d24297#code

pragma solidity ^0.8.0;

// ChatGPT generated interface
interface IcrvUSD {
    
    // ERC1271 interface
    function isValidSignature(bytes32 _hash, bytes calldata _signature) external view returns (bytes4);

    // Functions from the provided Vyper code
    function decimals() external view returns (uint8);
    function version() external view returns (string memory);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function salt() external view returns (bytes32);
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function nonces(address owner) external view returns (uint256);
    function minter() external view returns (address);

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool);
    function transfer(address _to, uint256 _value) external returns (bool);
    function approve(address _spender, uint256 _value) external returns (bool);
    function permit(address _owner, address _spender, uint256 _value, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external returns (bool);
    function increaseAllowance(address _spender, uint256 _add_value) external returns (bool);
    function decreaseAllowance(address _spender, uint256 _sub_value) external returns (bool);
    function burnFrom(address _from, uint256 _value) external returns (bool);
    function burn(uint256 _value) external returns (bool);
    function mint(address _to, uint256 _value) external returns (bool);
    function set_minter(address _minter) external;
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
