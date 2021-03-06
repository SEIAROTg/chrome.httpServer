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


# return a Promise to create a new socket
createSocket = () ->

	return new Promise (resolve, reject) ->
		chrome.sockets.tcpServer.create (socketInfo) ->
			resolve socketInfo


# return a Promise for socket listening
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
			_send socketId, @result, callback
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


# parse HTTP Request header
parseRequestHeader = (headerStr) ->

	result =
		header: {}

	headerArr = headerStr.split('\r\n')
	requestLine = headerArr[0].split(/\s+/)

	nHeader = headerArr.length - 1

	for j in [1..nHeader]
		p = headerArr[j].indexOf ':'
		key = headerArr[j].substr(0, p).trim()
		value = headerArr[j].substr(p + 1).trim()
		result.header[key] = value

	result.message =
		method: requestLine[0]
		url: requestLine[1]
		version: requestLine[2]

	return result


# build HTTP Response header string
buildResponseHeader = (statusCode, header, reasonPhrase) ->

	if not reasonPhrase?
		if statusCode of REASON_PHRASE
			reasonPhrase = REASON_PHRASE[statusCode]
		else
			reasonPhrase = ''

	headerStr = "HTTP/1.1 #{statusCode} #{reasonPhrase}\r\n"
	for key, value of header
		headerStr += "#{key}: #{value}\r\n"
	headerStr += '\r\n'

	return headerStr


class _http_request

	constructor: (headerStr) ->

		header = parseRequestHeader headerStr
		@header = header.header
		@message = header.message

		if @message.method == 'POST' and not @header['Content-Length']?
			throw Error 'Content-Length not specified'

		@length = 0
		@onData = (data) ->
		@onEnd = (data) ->


class _http_response

	constructor: (@socketId, @onReceiveHandler) ->

		@headWritten = false

	writeHead: (statusCode, header, reasonPhrase, callback) ->

		if @headWritten
			throw Error "HTTP header has already been written"

		if typeof reasonPhrase == 'function'
			callback = reasonPhrase
			reasonPhrase = null

		headerStr = buildResponseHeader statusCode, header, reasonPhrase

		chrome.sockets.tcp.send @socketId, headerStr, ((sendInfo) ->
			@headWritten = true
			if callback?
				callback sendInfo
		).bind @

	writeHeadPromise: (statusCode, header, reasonPhrase) ->

		return new Promise ((resolve, reject) ->
			@writeHead statusCode, header, reasonPhrase, (sendInfo) ->
				if sendInfo.resultCode < 0
					reject sendInfo
				else
					resolve sendInfo
		).bind @

	write: (data, callback) ->

		if not @headWritten
			@writeHead 200, {}, (() ->
				chrome.sockets.tcp.send @socketId, data, callback.bind(@)
		).bind @
		else
			chrome.sockets.tcp.send @socketId, data, callback.bind(@)

	writePromise: (data) ->

		return new Promise ((resolve, reject) ->
			@write data, (sendInfo) ->
				if sendInfo.result < 0
					reject sendInfo
				else
					resolve sendInfo
		).bind @

	end: (data) ->

		if data?
			@write data, (() ->
				@end()
			).bind @
		else
			chrome.sockets.tcp.close @socketId
			chrome.sockets.tcp.onReceive.removeListener @onReceiveHandler


class _http_session

	constructor: (@socketId, @callback) ->

		@headerInfo =
			data: new Uint8Array HEADER_MAX_LEN
			offset: 0
			length: 0
		@onReceiveHandler = @onReceive.bind @
		chrome.sockets.tcp.onReceive.addListener @onReceiveHandler
		chrome.sockets.tcp.onReceiveError.addListener @onReceiveError

	onReceive: (info) ->

		if info.socketId != @socketId
			return

		if @headerInfo.length != 0
			@onData info.data
		else
			data = new Uint8Array info.data

			len = Math.min data.length, HEADER_MAX_LEN - @headerInfo.offset
			
			for i in [0..len-1]
				
				if compare(data, HEADER_END, i, 0, HEADER_END_LEN) # header ends
					
					@headerInfo.length = @headerInfo.offset
					headerStr = String.fromCharCode.apply(null, @headerInfo.data.subarray(0, @headerInfo.length))

					try
						@req = new _http_request headerStr
					catch
						@error 400
						return
					@res = new _http_response(@socketId, @onReceiveHandler)

					@callback @req, @res

					if i + HEADER_END_LEN < len
						@onData data.buffer.slice(i + HEADER_END_LEN)

					break

				else
					@headerInfo.data[@headerInfo.offset] = data[i]
					++@headerInfo.offset

			if @headerInfo.offset == HEADER_MAX_LEN
				error 413

	onReceiveError: () ->

		@res.onError.bind(@res)() if @res?

	error: (statusCode) ->

		chrome.sockets.tcp.send @socketId, "HTTP/1.1 #{statusCode} #{REASON_PHRASE[statusCode]}", (() ->
			chrome.sockets.tcp.close @socketId
		).bind @

	onData: (data) ->

		contentLength = parseInt @req.header['Content-Length']
		len = data.byteLength
		if @req.length + len > contentLength
			@onData data.slice(0, contentLength - @req.length)
		else
			@req.length += data.byteLength
			@req.onData data
			if @req.length == contentLength
				@req.onEnd()


class _chrome_httpServer

	# callback should be like
	#     function(request, response) {...}
	constructor: (@callback) ->

	onAccept: (info) ->

		if info.socketId != @socketId
			return
		session = new _http_session info.clientSocketId, @callback
		chrome.sockets.tcp.setPaused info.clientSocketId, false

	listen: (port, addr = '0.0.0.0') ->

		return new Promise ((resolve, reject) ->
			createSocket()
			.then ((sckListen) ->
				@socketId = sckListen.socketId
				return listen @socketId, addr, port
			).bind @
			.then ((ret) ->
				chrome.sockets.tcpServer.onAccept.addListener @onAccept.bind(@)
				resolve()
			).bind @
			.then null, reject
		).bind @

	close: (callback=()->) ->

		chrome.sockets.tcpServer.close @socketId, callback


chrome.httpServer = _chrome_httpServer
