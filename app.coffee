Botkit = require('botkit')
controller = Botkit.slackbot(
	
)
bot = controller.spawn(
	token: 'xoxb-70992350358-Sbav8gt02ufdixeq5MGQx8dg'
)

bot.startRTM (err, bot, payload) ->
	if err
		throw new Error 'Could not connect to Slack'

	controller.storage.channels.save {id: 'test', test:'test'}, (err) ->
		console.log err
