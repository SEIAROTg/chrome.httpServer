# chrome.httpServer

chrome.httpServer a http server library for Google Chrome Apps depending on `chrome.sockets` API.

## Getting Started

To use chrome.httpServer, you need to compile it with the following commands because chrome.httpServer is written in coffee-script:

    > npm install
    > grunt

Then `chrome.httpServer.js` will be generated in `<project dir>/dest/`. Just include it in your `manifest.json`.

### Demo app

To compile together with the demo app, use the following commands instead:

    > npm install
    > grunt demo

Then you can go to `chrome://extensions/`, click `Load unpacked extension...` and choose `<project dir>/dest/demoApp` to load the demoApp.

Launch the app. It will listen at port 0x7777 (30583).

## Usage

### Create an server

    server = new chrome.httpServer(callback);
`callback` is the HTTP request handler with two parameters `request` and `response`.

### Listen 

    server.listen(port, optional hostname);
The default value of `hostname` is `0.0.0.0`

### Stop listening

    server.close();
    
### Process request

    server = new chrome.httpServer(function(req, res) {
        req.message.method // request method such as `GET`, `POST`
        req.message.url // request URL like "/index.html"
        req.message.version // HTTP version like "HTTP/1.1"
        req.header // header object
        req.header['Host']
        req.header['Acccept']
        ...
    });
    server.listen(0x7777, '127.0.0.1');
    
### Response

#### res.writeHead(statusCode, header, optional reasonPhrase, optional callback)

Send HTTP header.

    res.writeHead(200, {'Content-Type': 'text/plain'}, 'OK');
    
#### res.write(data, optional callback)

Send data. `data` can be `String` or `ArrayBuffer`

    res.write('It works!');
    
#### res.end(optional data)

End HTTP response.
    
    res.end();
    res.end('It works!');

#### Promise

Response offer methods which return a `Promise`. They have the same parameters as the above method but don't have parameter `callback`. They are:

    res.writeHeadPromise
    res.writePromise

### Process POST request

    server = new chrome.httpServer(function(req, res) {
        data = "" 
        
        req.onData = function(chunk) {
    		arr = new Uint8Array(chunk);
    		data += String.fromCharCode.apply(null, arr);
        }
        
        req.onEnd = function() {
            console.log(data);
        }
    });
    server.listen(0x7777, '127.0.0.1');

## Notes

* HTTP request header is defaultly restricted within 0x2000 bytes. It is defined in `HEADER_MAX_LEN`.
