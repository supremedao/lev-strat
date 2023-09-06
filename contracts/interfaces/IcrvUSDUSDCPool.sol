// https://etherscan.io/address/0x4dece678ceceb27446b35c672dc7d61f30bad69e

pragma solidity ^0.8.0;

// ChatGPT generated
contract IcrvUSDUSDCPool {
    // Corresponds to the `get_dy` function in the Vyper contract
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    // Corresponds to the `get_dx` function in the Vyper contract
    function get_dx(
        int128 i,
        int128 j,
        uint256 dy
    ) external view returns (uint256);

    // Corresponds to the `exchange` function in the Vyper contract
    function exchange(
        int128 i,
        int128 j,
        uint256 _dx,
        uint256 _min_dy,
        address _receiver
    ) external returns (uint256);
}
