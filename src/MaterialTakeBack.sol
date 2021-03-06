// SPDX-License-Identifier: MIT

pragma solidity ^0.6.7;

import "zeppelin-solidity/proxy/Initializable.sol";
import "zeppelin-solidity/token/ERC20/IERC20.sol";
import "ds-stop/stop.sol";
import "./interfaces/ISettingsRegistry.sol";
import "./interfaces/IMaterial.sol";

contract MaterialTakeBack is Initializable, DSStop {
    event TakebackMaterial(
        address account,
        uint256 nonce,
        uint128 id,
        uint256 tokenId,
        uint256 amount
    );
    event ClaimedTokens(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    bytes32 private constant CONTRACT_MATERIAL = "CONTRACT_MATERIAL";

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    ISettingsRegistry public registry;
    address public supervisor;
    uint256 public networkId;

    mapping(address => uint256) userToNonce;

    modifier isHuman() {
        require(msg.sender == tx.origin, "robot is not permitted");
        _;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    function initialize(address _registry, address _supervisor, uint256 _networkId) public initializer {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);
        registry = ISettingsRegistry(_registry);
        supervisor = _supervisor;
        networkId = _networkId;

        _status = _NOT_ENTERED;
    }

    // _hashmessage = hash("${address(this)}{_user}${networkid}${ids[]}${amounts[]}")
    // _v, _r, _s are from supervisor's signature on _hashmessage
    // takeback(...) is invoked by the user who want to claim material.
    // while the _hashmessage is signed by supervisor
    function takeback(
        uint256 _nonce,
        uint128[] memory _ids,
        uint256[] memory _amounts,
        bytes32 _hashmessage,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public nonReentrant isHuman stoppable {
        address _user = msg.sender;
        require(userToNonce[_user] == _nonce, "invaild nonce");
        // verify the _hashmessage is signed by supervisor
        require(
            supervisor == _verify(_hashmessage, _v, _r, _s),
            "verify failed"
        );
        // verify that the address(this), _user, networkId, _ids, _amounts are exactly what they should be
        require(
            keccak256(
                abi.encodePacked(address(this), _user, _nonce, networkId, _ids, _amounts)
            ) == _hashmessage,
            "hash invaild"
        );
        require(_ids.length == _amounts.length, "invaild length");
        require(_ids.length > 0, "no id");
        userToNonce[_user] += 1;
        for (uint256 i = 0; i < _ids.length; i++) {
            uint128 id = _ids[i];
            uint256 amount = _amounts[i];
            uint256 tokenId = _rewardMaterial(_user, id, amount);
            emit TakebackMaterial(_user, _nonce, id, tokenId, amount);
        }
    }

    function _rewardMaterial(address account, uint128 id, uint256 amount) internal returns (uint256) {
        address material = registry.addressOf(CONTRACT_MATERIAL);
        return IMaterial(material).mintObject(account, id, amount, "");
    }

    function _verify(
        bytes32 _hashmessage,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public pure returns (address) {
        bytes memory prefix = "\x19EvolutionLand Signed Message:\n32";
        bytes32 prefixedHash =
            keccak256(abi.encodePacked(prefix, _hashmessage));
        address signer = ecrecover(prefixedHash, _v, _r, _s);
        return signer;
    }

    function changeSupervisor(address _newSupervisor) public auth {
        supervisor = _newSupervisor;
    }

    function claimTokens(address _token) public auth {
        if (_token == address(0)) {
            _makePayable(owner).transfer(address(this).balance);
            return;
        }
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner, balance);
        emit ClaimedTokens(_token, owner, balance);
    }

    function _makePayable(address x) internal pure returns (address payable) {
        return address(uint160(x));
    }
}
