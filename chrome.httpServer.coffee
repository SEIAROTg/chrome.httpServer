HEADER_MAX_LEN = 0x2000
HEADER_END = [13, 10, 13, 10] #'\r\n\r\n'
HEADER_END_LEN = HEADER_END.length

REASON_PHRASE =
	100 : 'Continue',
	101 : 'Switching Protocols',
	102 : 'Processing',                 # RFC 2518, obsoleted by RFC 4918
	200 : 'OK',
	201 : 'Created',
	202 : 'Accepted',
	203 : 'Non-Authoritative Information',
	204 : 'No Content',
	205 : 'Reset Content',
	206 : 'Partial Content',
	207 : 'Multi-Status',               # RFC 4918
	300 : 'Multiple Choices',
	301 : 'Moved Permanently',
	302 : 'Moved Temporarily',
	303 : 'See Other',
	304 : 'Not Modified',
	305 : 'Use Proxy',
	307 : 'Temporary Redirect',
	308 : 'Permanent Redirect',         # RFC 7238
	400 : 'Bad Request',
	401 : 'Unauthorized',
	402 : 'Payment Required',
	403 : 'Forbidden',
	404 : 'Not Found',
	405 : 'Method Not Allowed',
	406 : 'Not Acceptable',
	407 : 'Proxy Authentication Required',
	408 : 'Request Time-out',
	409 : 'Conflict',
	410 : 'Gone',
	411 : 'Length Required',
	412 : 'Precondition Failed',
	413 : 'Request Entity Too Large',
	414 : 'Request-URI Too Large',
	415 : 'Unsupported Media Type',
	416 : 'Requested Range Not Satisfiable',
	417 : 'Expectation Failed',
	418 : 'I\'m a teapot',              # RFC 2324
	422 : 'Unprocessable Entity',       # RFC 4918
	423 : 'Locked',                     # RFC 4918
	424 : 'Failed Dependency',          # RFC 4918
	425 : 'Unordered Collection',       # RFC 4918
	426 : 'Upgrade Required',           # RFC 2817
	428 : 'Precondition Required',      # RFC 6585
	429 : 'Too Many Requests',          # RFC 6585
	431 : 'Request Header Fields Too Large',# RFC 6585
	500 : 'Internal Server Error',
	501 : 'Not Implemented',
	502 : 'Bad Gateway',
	503 : 'Service Unavailable',
	504 : 'Gateway Time-out',
	505 : 'HTTP Version Not Supported',
	506 : 'Variant Also Negotiates',    # RFC 2295
	507 : 'Insufficient Storage',       # RFC 4918
	509 : 'Bandwidth Limit Exceeded',
	510 : 'Not Extended',               # RFC 2774
	511 : 'Network Authentication Required' # RFC 6585


createSocket = () ->

	return new Promise (resolve, reject) ->
		chrome.sockets.tcpServer.create (socketInfo) ->
			resolve socketInfo


listen = (socketId, addr, port) ->

	return new Promise (resolve, reject) ->
		chrome.sockets.tcpServer.listen socketId, addr, port, (ret) ->
			if ret < 0
				reject ret
			else 
				resolve ret


# add string support for chrome.sockets.tcp.send
_send = chrome.sockets.tcp.send
chrome.sockets.tcp.send = (socketId, data, callback=()->) ->
	if typeof data == 'string' # if data is string, convert it to ArrayBuffer
		blob = new Blob [data]
		fileReader = new FileReader()
		fileReader.onload = () ->
			_send socketId, this.result, callback
		fileReader.readAsArrayBuffer blob
	else
		_send socketId, data, callback


# compare two array-like object A and B with offset and length limit
# return True if same and False otherwise
compare = (A, B, offsetA, offsetB, len) ->
	
	if offsetA + len > A.length or offsetB + len > B.length
		return false

	while len
		return false if parseInt(A[offsetA]) != parseInt(B[offsetB])
		++offsetA
		++offsetB
		--len

	return true


class _http_request

	onData: (data) ->


class _http_response

	headWritten = false
	self = {}

	constructor: (@socketId, @onReceive) ->
		`self = this`
		headWritten = false

	writeHead: (statusCode, header, reasonPhrase) ->
		if headWritten
			throw Error "HTTP header has already been written"
		else
			if not reasonPhrase?
				if statusCode in REASON_PHRASE
					reasonPhrase = REASON_PHRASE[statusCode]
				else
					reasonPhrase = ''
			headerStr = 'HTTP/1.1 ' + statusCode + ' ' + reasonPhrase + '\r\n'
			for key, value of header
				headerStr = headerStr.concat key + ': ' + value + '\r\n'
			headerStr = headerStr.concat '\r\n'
			
			chrome.sockets.tcp.send @socketId, headerStr, () ->
				headWritten = true

	write: (data, callback) ->
		if not headWritten
			headWritten = true
		chrome.sockets.tcp.send @socketId, data, callback

	end: (data) ->
		if data?
			@write data, () ->
				self.end()
		else
			chrome.sockets.tcp.close @socketId
			chrome.sockets.tcp.onReceive.removeListener @onReceive


class _chrome_httpServer

	callback = null

	onAccept = (info) ->
		if info.socketId == @socketId

			socketId = info.clientSocketId

			headerInfo =
				data: new Uint8Array HEADER_MAX_LEN
				offset: 0
				length: 0

			req = new _http_request()

			onReceive = (info) ->
				if info.socketId == socketId

					if headerInfo.length == 0

						data = new Uint8Array info.data

						len0 = data.length
						len1 = HEADER_MAX_LEN - headerInfo.offset
						if len0 < len1
							len = len0
						else 
							len = len1 + 1
						
						for i in [0..len-1]
							
							if compare(data, HEADER_END, i, 0, HEADER_END_LEN) # header ends
								
								headerInfo.length = headerInfo.offset + 1

								headerStr = String.fromCharCode.apply(null, headerInfo.data)
								headerArr = headerStr.split('\r\n')
								requestLine = headerArr[0].split(/\s+/)

								nHeader = headerArr.length - 1
								header = {}
								for i in [1..nHeader]
									entry = headerArr[i].split(':')
									key = entry[0].trim()
									value = entry[1].trim()
									header[key] = value

								message =
									method: requestLine[0]
									url: requestLine[1]
									version: requestLine[2]

								req.message = message
								req.header = header

								res = new _http_response(socketId, onReceive)
								
								callback(req, res)

								if i + HEADER_END_LEN <= len
									req.onData data.subarray(i + HEADER_END_LEN).buffer
								break
							else
								headerInfo.data[headerInfo.offset] = data[i]
								++headerInfo.offset

						if headerInfo.offset == HEADER_MAX_LEN
							chrome.sockets.tcp.send socketId, 'HTTP/1.1 413 Entity Too Large', () ->
								chrome.sockets.tcp.close socketId
					else # headerLength[0] != 0
						req.onData info.data

			chrome.sockets.tcp.onReceive.addListener onReceive
			chrome.sockets.tcp.setPaused socketId, false


	# callback should be like
	#     function(request, response) {...}
	constructor: (_callback) ->
		callback = _callback

	listen: (port, addr = '0.0.0.0') ->
		createSocket()
		.then (sckListen) ->
			@socketId = sckListen.socketId
			return listen @socketId, addr, port
		.then (ret) ->
				chrome.sockets.tcpServer.onAccept.addListener onAccept
			, (ret) ->
				return false


`chrome.httpServer = _chrome_httpServer`