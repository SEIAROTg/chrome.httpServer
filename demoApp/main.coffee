# convert string to ArrayBuffer
#
# unsafe for multi-byte encoding, should use TextEncoder polyfill instead.
# but TextEncoder has not been implemented in chrome yet
string2binary = (string) ->
	
	buf = new ArrayBuffer string.length
	bufv = new Uint8Array buf
	len = string.length
	for i in [0..len]
		bufv[i] = string.charCodeAt(i)
	return buf

chrome.app.runtime.onLaunched.addListener (intentData) ->

	server = new chrome.httpServer (req, res) ->
		res.writeHead 200, {'Content-Type': 'text/html'}
		res.end string2binary('<h1>It works!</h1>')

	server.listen 0x7777, '127.0.0.1'
