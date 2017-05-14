module.exports =
    parkingSpaces: 5
    weeksBetweenWins: 1
    admins: []
    slackBotToken: process.env.SLACK_BOT_TOKEN
    debug: if process.env.NODE_ENV isnt 'production' then true else false
    drawWinnersImages: ['http://i.imgur.com/ZMFVgC1.png']
