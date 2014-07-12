chrome.app.runtime.onLaunched.addListener (intentData) ->

	server = new chrome.httpServer (req, res) ->
		res.writeHead 200, {'Content-Type': 'text/html'}
		res.end '<h1>It works!</h1>'

	server.listen 0x7777, '127.0.0.1'
