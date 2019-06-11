pragma solidity ^0.5.8;

contract iotdex {
    
    enum EncryptionScheme { DES, DES3,  AES128, AES256 }
    /* contract owner */
    address private creator;


    /* metadata from a specific sensor type */
    struct metadata {
        address device_id;
        uint timestamp;
        string ipfs;
        string schema;
        uint key_index;
        EncryptionScheme encryption_scheme;
        string encrypted_key;
    }

    /* everything about producers */
    struct producer {
        string name;
        // producer supported sensor types
        mapping(uint => bool) types;
        // unit prices for every sensor type
        mapping(uint => uint) prices;
        // payload from a specific sensor type
        mapping(uint => metadata[]) metadatas;
        // devices belong to specific producer
        mapping(address => bool) devices;
    }

    struct customer{
        metadata[] paid_arr;
        string pub_key;
    }

    mapping(address => producer) private producer_map;
    mapping(address => customer) private customer_map;
    address[] private producer_arr;
    mapping(address => uint) balances;

    function getEncryptionScheme(uint _encID) private pure returns (EncryptionScheme){
        if(_encID==0) return EncryptionScheme.DES;
        if(_encID==1) return EncryptionScheme.DES3;
        if(_encID==2) return EncryptionScheme.AES128;
        if(_encID==3) return EncryptionScheme.AES256;
        revert();
    }
    
    
    /// @dev Registers a producer on data exchange to be able to list their sensors metadata
    /// @param name for producer which is shown on data exchange
    /// @param sensors list of sensor types producer will publish on data exchange
    /// @param costs list of prices corresponding to each sensor
    /// @return result succesfully registered or not 
    function producer_register (string memory name, uint[] memory sensors, uint[] memory costs) public returns (address) {
        // check if producer is already registered .
        require(bytes(producer_map[msg.sender].name).length == 0);
        producer_map[msg.sender].name = name;
        for (uint it = 0; it < sensors.length; it++) {
            producer_map[msg.sender].types[sensors[it]] = true;
            producer_map[msg.sender].prices[sensors[it]] = costs[it];
        }
        // add prodcuer address to "producer array" 
        producer_arr.push(msg.sender);
        return msg.sender;
    }
    
    /// @dev Registers a customer to data exchange 
    /// @param _pub_key Customer's public key which is required to encrypt key exchange between parties  
    /// @return address of registered customer if succesfull
    
    function customer_register (string memory _pub_key) public returns (address) {
        // check if customer is already registered .
        require(bytes(customer_map[msg.sender].pub_key).length == 0);
        customer_map[msg.sender].pub_key = _pub_key;
        return msg.sender;
    }
    

    /// @dev Add devices address that can push data on behalf of producer
    /// @param device_address Address of the device that allowed to push data 
    /// @return Address of current added device
    function device_register (address device_address) public returns (address) {
        require(!producer_map[msg.sender].devices[device_address]);
        producer_map[msg.sender].devices[device_address] = true;
        return device_address;
    }



    /// @dev Get symbol of the producer to be listed
    /// @param addr Address of the producer 
    /// @return prefix corresponding symbol to producer's address
    function get_producer (address addr) public view returns (string memory name) {
        return (producer_map[addr].name);
    }

    /// @dev Adds the data to be shown on market
    /// @param producer_address Address of the producer 
    /// @param sensor_type represents data belongs to which sensor type
    /// @param schema JSON representation of schema representation of data
    /// @param timestamp time when data is pushed on ipfs
    /// @param ipfs url of the content on ipfs  
    function publish_metadata (address producer_address, uint  sensor_type, string memory schema, uint timestamp, string memory ipfs,uint  key_index, uint  _encID ) public returns (address) {
        require(producer_map[producer_address].types[sensor_type] && producer_map[producer_address].devices[msg.sender]);
        producer_map[producer_address].metadatas[sensor_type].push(metadata(msg.sender,timestamp,ipfs,schema,key_index, getEncryptionScheme(_encID),""));
        return producer_address;
    }

    /// @dev Checks whether producer has sensor_type or not, returns address if producer has
    /// @param sensor_type numeric representation of corresponding sensor_type
    /// @param index iteration number for producer_list
    function query_sensor_type (uint sensor_type, uint index) public view returns (address result) {
        require(producer_map[producer_arr[index]].types[sensor_type] && producer_map[producer_arr[index]].metadatas[sensor_type].length > 0);
        return producer_arr[index];
    }

    /// @dev Getting data from the producer for specific sensor. It's complementary to query from application
    /// @param producer_address address of the producer who has data for queried sensor metadata
    /// @param sensor_type Look-up sensor types
    /// @param index The position of metadata since vendor may have multiple data for one sensor type 
    /// @return all metadata except ipfs url and corresponding price to sensor type 
    function sensor_metadata (address producer_address, uint sensor_type, uint index) public view returns (string memory schema, uint timestamp, uint price) {
        return (producer_map[producer_address].metadatas[sensor_type][index].schema,
                producer_map[producer_address].metadatas[sensor_type][index].timestamp,
                producer_map[producer_address].prices[sensor_type]);
    }
    

    /// @dev makes transaction between producer and consumer while providing ipfs url to buyer
    /// @param producer_address Address of the producer 
    /// @param sensor_type Sensor type which data belongs to
    /// @param index Position of asked metadata in array
    /// @return returns address of the producer if metadata_request event is succesfully requested
    function request_data (address producer_address, uint sensor_type, uint index) public returns (address) {
        uint sensor_price = producer_map[producer_address].prices[sensor_type];
        require(sensor_price<=balances[msg.sender]);
        emit metadata_request(msg.sender,producer_address,customer_map[msg.sender].pub_key,sensor_type,index);
        return producer_address;
        
    }
    
    event metadata_request(
        address indexed _from,
        address indexed _to,
        string pub_key,
        uint sensor_type,
        uint index
    );

    event metadata_response(
        address indexed _from,
        address indexed _to,
        string dec_key,
        uint sensor_type,
        uint index,
        string ipfs
    );
    
    function transfer_key(string memory dec_key,address _to, uint sensor_type, uint index) public returns (string memory) {
        uint _price = producer_map[msg.sender].prices[sensor_type];
        require(balances[_to] >= _price);
        balances[_to] -= _price;
        balances[msg.sender] += _price;
        (producer_map[msg.sender].metadatas[sensor_type])[index].encrypted_key=dec_key;
        customer_map[_to].paid_arr.push((producer_map[msg.sender].metadatas[sensor_type])[index]);
        emit metadata_response(msg.sender,_to,dec_key, sensor_type,index,(producer_map[msg.sender].metadatas[sensor_type])[index].ipfs);
        return dec_key;
    }
    
    
    function deposit() payable public returns (bool) {
        balances[msg.sender] += msg.value;
        return true;
    }
    
    
    function withdraw() public {
        uint amountToWithdraw = balances[msg.sender];
        balances[msg.sender] = 0;
        msg.sender.transfer(amountToWithdraw); 
        
    }
    
    
    
    
    function update_sensor_price (uint sensor_type, uint price) public returns (uint) {
        require(producer_map[msg.sender].types[sensor_type]);
        producer_map[msg.sender].prices[sensor_type] = price;
        return price;
    }

    function get_sensor_price(uint sensor_type_index) public view returns (uint) {
        if (producer_map[msg.sender].types[sensor_type_index] != true) {
            return 0;
        } else {
            return producer_map[msg.sender].prices[sensor_type_index];
        }
    }
    
    /// @dev fallback function that accepts ether to be sent to the contract 
    /// function () public payable {}
    
    /// @dev constructor 
    constructor() public {
        creator = msg.sender;
    }

    /// @dev kills contract and sends remaining funds back to creator 
    function kill() public {
        if (msg.sender == creator) {
            ///selfdestruct(creator);
            selfdestruct(address(uint160(creator)));

        }
    }

}
