nodeEnv = process.env.NODE_ENV or 'development'

module.exports =
    parkingSpaces: 5 # Amount of spaces up for grabs
    weeksBetweenWins: 1 # Amount of weeks before a winner can win again
    admins: [] # Array of slack usernames
    slackBotToken: process.env.SLACK_BOT_TOKEN
    debug: if nodeEnv is 'development' then true else false
    # Array of images to show when drawing winners
    # Randomly picked for each draw if more than one image.
    drawWinnersImages: ['http://i.imgur.com/ZMFVgC1.png']
