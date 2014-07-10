module.exports = (grunt) ->
	grunt.initConfig
		pkg: grunt.file.readJSON 'package.json'
		watch:
			main:
				files: ['chrome.httpServer.coffee']
				tasks: [
					'coffee:main',
					'copy:lib'
				]
				options:
					spawn: false
			demo:
				files: ['demoApp/main.coffee']
				tasks: ['coffee:demo']
				options:
					spawn: false
			manifest:
				files: ['demoApp/manifest.json']
				tasks: ['copy:manifest']
				options:
					spawn: false
		coffee:
			main:
				files:
					'dest/chrome.httpServer.js': 'chrome.httpServer.coffee'
			demo:
				files:
					'dest/demoApp/main.js': 'demoApp/main.coffee'
		clean:
			dest:
				src: ['dest']
		uglify:
			main:
				files:
					'dest/chrome.httpServer.js': 'dest/chrome.httpServer.js'
			demo:
				files:
					'dest/demoApp/main.js': 'dest/demoApp/main.js'
		copy:
			manifest:
				files: [
					expand: true
					cwd: 'demoApp/'
					src: 'manifest.json'
					dest: 'dest/demoApp/'
				]
			lib:
				files: [
					expand: true
					cwd: 'dest/'
					src: 'chrome.httpServer.js'
					dest: 'dest/demoApp/'
				]
	
	grunt.loadNpmTasks 'grunt-contrib-watch'
	grunt.loadNpmTasks 'grunt-contrib-coffee'
	grunt.loadNpmTasks 'grunt-contrib-copy'
	grunt.loadNpmTasks 'grunt-contrib-uglify'
	grunt.loadNpmTasks 'grunt-contrib-clean'
	
	grunt.registerTask 'default', ['coffee:main']
	grunt.registerTask 'demo', [
		'coffee',
		'uglify',
		'copy'
	]

	grunt.registerTask 'dev', [
		'clean'
		'coffee'
		'copy'
		'watch'
	]
