pragma solidity ^0.6.7;

import "zeppelin-solidity/proxy/Initializable.sol";
import "zeppelin-solidity/introspection/ERC165.sol";
import "zeppelin-solidity/token/ERC721/IERC721.sol";
import "ds-auth/auth.sol";
import "./interfaces/ISettingsRegistry.sol";
import "./interfaces/ITokenUse.sol";

contract PveTeam is Initializable, ERC165, DSAuth {
    event Join(address user, uint256 slot, uint256 tokenId);
    event Exit(address user, uint256 slot, uint256 tokenId);

    bytes4 internal constant InterfaceId_IActivity = 0x6086e7f8;
    // 0x434f4e54524143545f544f4b454e5f5553450000000000000000000000000000
    bytes32 internal constant CONTRACT_TOKEN_USE = "CONTRACT_TOKEN_USE";
    bytes32 internal constant CONTRACT_OBJECT_OWNERSHIP = "CONTRACT_OBJECT_OWNERSHIP";

    uint256 public constant TEAM_ID = 1;
    uint256 public constant MAX_TEAM_SIZE = 4;

    struct TeamInfo {
        address user;
        uint256 slot;
    }

    ISettingsRegistry public registry;
    // user => (slot => tokenId)
    mapping (address => mapping(uint256 => uint256)) public teams;
    // tokenId => info
    mapping (uint256 => TeamInfo) public infos;

    mapping(address => uint256) public teamLock;
    uint256 public lock;

    function initialize(address _registry) public initializer {
        owner = msg.sender;
        emit LogSetOwner(msg.sender);
        registry = ISettingsRegistry(_registry);
        lock = 1 days;

        _registerInterface(InterfaceId_IActivity);
    }

    function joins(uint256[] calldata slots, uint256[] calldata tokenIds) external {
        for(uint256 i = 0; i < tokenIds.length; i++) {
            join(slots[i], tokenIds[i]);
        }
    }

    function exits(uint256[] calldata tokenIds) external {
        for(uint256 i = 0; i < tokenIds.length; i++) {
            exit(tokenIds[i]);
        }
    }

    function join(uint256 slot, uint256 tokenId) public {
        address tokenuse = registry.addressOf(CONTRACT_TOKEN_USE);
        require(ITokenUse(tokenuse).getTokenUser(tokenId) == address(0), "Team: HIRE_FORBIDDEN");
        require(infos[tokenId].user == address(0), "Team: ALREADY_INTEAM");
        ITokenUse(tokenuse).addActivity(tokenId, msg.sender, 0);
        require(slot < MAX_TEAM_SIZE, "Team: INVALID_SLOT");
        require(teams[msg.sender][slot] == 0, "Team: OCCUPIED");
        teams[msg.sender][slot] = tokenId;
        infos[tokenId] = TeamInfo({
            user: msg.sender,
            slot: slot
        });
        if (fullTeam(msg.sender)) {
            teamLock[msg.sender] = block.timestamp + lock;
        }
        emit Join(msg.sender, slot, tokenId);
    }

    function _exit(uint256 tokenId) internal {
        TeamInfo memory info = infos[tokenId];
        require(info.user != address(0), "Team: NOT_INTEAM");
        require(tokenId != 0, "Team: EMPTY");
        require(unlocked(info.user), "Team: LOCKED");
        delete teams[info.user][info.slot];
        delete infos[tokenId];
        emit Exit(info.user, info.slot, tokenId);
    }

    function exit(uint256 tokenId) public {
        address ownership = registry.addressOf(CONTRACT_OBJECT_OWNERSHIP);
        address tokenuse = registry.addressOf(CONTRACT_TOKEN_USE);
        if (IERC721(ownership).ownerOf(tokenId) == msg.sender) {
            ITokenUse(tokenuse).removeActivity(tokenId, msg.sender);
        } else {
            require(msg.sender == infos[tokenId].user, "Team: ONLY_USER");
            ITokenUse(tokenuse).removeActivity(tokenId, address(0));
        }
    }

    function swap(uint256 slot, uint256 newTokenId) public {
        uint256 tokenId = teams[msg.sender][slot];
        exit(tokenId);
        join(slot, newTokenId);
    }

    function activityStopped(uint256 tokenId) public auth {
        _exit(tokenId);
    }

    function setLock(uint256 newlock) auth public {
        lock = newlock;
    }

    function at(address user, uint256 slot) public view returns (uint256) {
        return teams[user][slot];
    }

    function exist(address user, uint256 slot) public view returns (bool) {
        return teams[user][slot] != 0;
    }

    function fullTeam(address user) public view returns (bool) {
        uint256 count = 0;
        for (uint256 slot = 0; slot < MAX_TEAM_SIZE; slot++) {
            if (exist(user, slot)) {
                count++;
            }
        }
        return count == MAX_TEAM_SIZE;
    }

    function unlocked(address user) public view returns (bool) {
        return teamLock[user] < block.timestamp;
    }

}
