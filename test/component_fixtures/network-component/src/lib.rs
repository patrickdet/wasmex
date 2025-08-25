#[allow(warnings)]
mod bindings;

use bindings::exports::test::network::types::{
    Guest as TypesGuest, 
    GuestTcpSocket, GuestUdpSocket, GuestHttpClient, GuestHttpResponse,
    TcpSocket as TypesTcpSocket, UdpSocket as TypesUdpSocket, 
    HttpClient as TypesHttpClient, HttpResponse as TypesHttpResponse,
};
use bindings::Guest;
use std::cell::RefCell;

struct NetworkComponent;

impl Guest for NetworkComponent {
    fn test() -> String {
        "Network resource test component".to_string()
    }
}

impl TypesGuest for NetworkComponent {
    type TcpSocket = TcpSocketImpl;
    type UdpSocket = UdpSocketImpl;
    type HttpClient = HttpClientImpl;
    type HttpResponse = HttpResponseImpl;
    
    fn create_tcp_socket() -> TypesTcpSocket {
        TypesTcpSocket::new(TcpSocketImpl {
            connected: RefCell::new(false),
            address: RefCell::new(None),
            port: RefCell::new(None),
            data_buffer: RefCell::new(Vec::new()),
        })
    }
    
    fn create_udp_socket() -> TypesUdpSocket {
        TypesUdpSocket::new(UdpSocketImpl {
            bound: RefCell::new(false),
            address: RefCell::new(None),
            port: RefCell::new(None),
            received_packets: RefCell::new(Vec::new()),
        })
    }
    
    fn create_http_client() -> TypesHttpClient {
        TypesHttpClient::new(HttpClientImpl {})
    }
}

struct TcpSocketImpl {
    connected: RefCell<bool>,
    address: RefCell<Option<String>>,
    port: RefCell<Option<u16>>,
    data_buffer: RefCell<Vec<u8>>,
}

impl GuestTcpSocket for TcpSocketImpl {
    fn connect(&self, address: String, port: u16) -> Result<(), String> {
        if *self.connected.borrow() {
            return Err("Already connected".to_string());
        }
        *self.connected.borrow_mut() = true;
        *self.address.borrow_mut() = Some(address.clone());
        *self.port.borrow_mut() = Some(port);
        Ok(())
    }
    
    fn write(&self, data: Vec<u8>) -> Result<u32, String> {
        if !*self.connected.borrow() {
            return Err("Not connected".to_string());
        }
        let len = data.len() as u32;
        self.data_buffer.borrow_mut().extend(data);
        Ok(len)
    }
    
    fn read(&self, length: u32) -> Result<Vec<u8>, String> {
        if !*self.connected.borrow() {
            return Err("Not connected".to_string());
        }
        let mut buffer = self.data_buffer.borrow_mut();
        let to_read = (length as usize).min(buffer.len());
        let data = buffer.drain(..to_read).collect();
        Ok(data)
    }
    
    fn close(&self) {
        *self.connected.borrow_mut() = false;
        *self.address.borrow_mut() = None;
        *self.port.borrow_mut() = None;
        self.data_buffer.borrow_mut().clear();
    }
}

struct UdpSocketImpl {
    bound: RefCell<bool>,
    address: RefCell<Option<String>>,
    port: RefCell<Option<u16>>,
    received_packets: RefCell<Vec<(Vec<u8>, String, u16)>>,
}

impl GuestUdpSocket for UdpSocketImpl {
    fn bind(&self, address: String, port: u16) -> Result<(), String> {
        if *self.bound.borrow() {
            return Err("Already bound".to_string());
        }
        *self.bound.borrow_mut() = true;
        *self.address.borrow_mut() = Some(address);
        *self.port.borrow_mut() = Some(port);
        Ok(())
    }
    
    fn send_to(&self, data: Vec<u8>, _address: String, _port: u16) -> Result<u32, String> {
        if !*self.bound.borrow() {
            return Err("Socket not bound".to_string());
        }
        Ok(data.len() as u32)
    }
    
    fn receive_from(&self, length: u32) -> Result<(Vec<u8>, String, u16), String> {
        if !*self.bound.borrow() {
            return Err("Socket not bound".to_string());
        }
        
        let mut packets = self.received_packets.borrow_mut();
        if packets.is_empty() {
            let dummy_data = vec![0u8; length.min(100) as usize];
            Ok((dummy_data, "127.0.0.1".to_string(), 8080))
        } else {
            packets.pop()
                .ok_or_else(|| "No packets available".to_string())
        }
    }
    
    fn close(&self) {
        *self.bound.borrow_mut() = false;
        *self.address.borrow_mut() = None;
        *self.port.borrow_mut() = None;
        self.received_packets.borrow_mut().clear();
    }
}

struct HttpClientImpl {}

impl GuestHttpClient for HttpClientImpl {
    fn request(&self, method: String, url: String, _headers: Vec<(String, String)>, _body: Option<Vec<u8>>) -> Result<TypesHttpResponse, String> {
        Ok(TypesHttpResponse::new(HttpResponseImpl {
            status_code: RefCell::new(200),
            headers_list: RefCell::new(vec![
                ("content-type".to_string(), "text/plain".to_string()),
                ("content-length".to_string(), "13".to_string()),
            ]),
            body_data: RefCell::new(format!("{} {}", method, url).into_bytes()),
        }))
    }
}

struct HttpResponseImpl {
    status_code: RefCell<u16>,
    headers_list: RefCell<Vec<(String, String)>>,
    body_data: RefCell<Vec<u8>>,
}

impl GuestHttpResponse for HttpResponseImpl {
    fn status(&self) -> u16 {
        *self.status_code.borrow()
    }
    
    fn headers(&self) -> Vec<(String, String)> {
        self.headers_list.borrow().clone()
    }
    
    fn body(&self) -> Result<Vec<u8>, String> {
        Ok(self.body_data.borrow().clone())
    }
}

bindings::export!(NetworkComponent with_types_in bindings);