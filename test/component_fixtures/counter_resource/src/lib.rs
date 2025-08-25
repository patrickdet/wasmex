#[allow(warnings)]
mod bindings;

use bindings::exports::counter::api::counters::Guest as CountersGuest;
use bindings::exports::counter::api::counters::GuestCounter;
use std::cell::RefCell;

struct Component;

// Counter resource implementation
pub struct Counter {
    value: RefCell<u32>,
}

impl bindings::Guest for Component {
    fn test_counter() -> String {
        String::from("Counter component loaded successfully")
    }
}

impl CountersGuest for Component {
    type Counter = Counter;
    
    fn use_counter(c: &Counter) -> u32 {
        c.get_value()
    }
    
    fn consume_counter(c: Counter) -> u32 {
        c.get_value()
    }
    
    fn make_counter(initial: u32) -> Counter {
        Counter::new(initial)
    }
}

impl GuestCounter for Counter {
    fn new(initial: u32) -> Self {
        Counter {
            value: RefCell::new(initial),
        }
    }
    
    fn increment(&self) -> u32 {
        let mut val = self.value.borrow_mut();
        *val += 1;
        *val
    }
    
    fn get_value(&self) -> u32 {
        *self.value.borrow()
    }
    
    fn reset(&self, value: u32) {
        *self.value.borrow_mut() = value;
    }
    
    fn add(&self, other: &Counter) -> u32 {
        *self.value.borrow() + *other.value.borrow()
    }
}

bindings::export!(Component with_types_in bindings);