contract;

use std::{
auth::msg_sender,
call_frames::msg_asset_id,
context::{
msg_amount,
this_balance,
},
asset::transfer,
hash:Hash,
};

struct Item {
id: u64,
price: u64,
owner: Identity,
metadata: str[20],
total_bought: u64,
}

abi SwayStore {
// a function to list an item for sale
// takes the price and metadata as args
#[storage(read, write)]
fn list_item(price: u64, metadata: str[20]);

// a function to buy an item
// takes the item id as the arg
#[storage(read, write), payable]
fn buy_item(item_id: u64);

// a function to get a certain item
#[storage(read)]
fn get_item(item_id: u64) -> Item;

// a function to set the contract owner
#[storage(read, write)]
fn initialize_owner() -> Identity;

//a function to withdraw contract funds
#[storage(read)]
fn withdraw_funds();

// return the number of items listed
#[storage(read)]
fn get_count() -> u64;
}

storage {
// counter for total items listed
item_counter: u64 = 0,

// map of item IDs to Items
item_map: StorageMap<u64, Item> = StorageMap {},

// owner of the contract
owner: Option<Identity> = Option::None,
}
