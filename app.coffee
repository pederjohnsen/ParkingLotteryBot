_ = require('underscore')
moment = require('moment')
async = require('async')
Botkit = require('botkit')

config = require('./config')

controller = Botkit.slackbot(
    debug: config.debug
    json_file_store: './data'
)

bot = controller.spawn(
    token: config.slackBotToken
)

bot.startRTM (err, bot, payload) ->
    if err
        throw new Error 'Could not connect to Slack'

    controller.hears ['\\bhello\\b', '\\bhi\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        controller.storage.users.get message.user, (err, user) ->
            if err
                bot.botkit.log('Failed to get user data.', err)

            if user
                bot.reply message, "Hello #{user.userLink}!"
            else
                bot.reply message, 'Hello!'

    controller.hears ['\\bhelp\\b', '\\binfo\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        messages = [
            "You can join by typing 'join @parkinglottery' & leave by typing 'leave @parkinglottery'."
            "Typing 'current @parkinglottery' tells you the current weeks winners, typing 'upcoming @parkinglottery' tells you the upcoming weeks winners."
        ]

        attachment =
            fallback: messages.join('\n')
            text: messages.join('\n')
            color: 'good'

        replyWithAttachments =
            text: "I'm the Parking Lottery bot."
            attachments: [attachment]
            timestamp: message.ts

        bot.reply message, replyWithAttachments

    controller.hears ['\\bgive me a parking space\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        if message.user isnt 'U1XPZ8H46'
            bot.api.reactions.add
                timestamp: message.ts
                channel: message.channel
                name: 'suspect'
            , (err, response) ->
                if err
                    bot.botkit.log('Failed to add emoji reaction.', err)

            bot.reply message, "I can't do that!"
        else
            data = {}

            getRandomWinner = (next) ->
                {currentWeek, currentYear} = getCurrentWeekDates()

                controller.storage.users.all (err, users) ->
                    if err
                        bot.botkit.log('Error getting users.', err)

                    currentWinners = _(users)
                        .chain()
                        .filter (user) ->
                            recentWin = _(user.recentWins).findWhere({week: currentWeek, year: currentYear})
                            recentWin and (!recentWin.donated or recentWin.donated is true)
                        .value()

                    if !currentWinners.length
                        next new Error 'No winners.'
                    else
                        data.randomWinner = _.sample(currentWinners, 1)?[0]
                        next null

            async.waterfall [
                getRandomWinner
            ], (err) ->
                if err
                    bot.botkit.log('Error giving space.', err)

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: 'innocent'
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                text = "*Sure <@#{message.user}>!*"
                attachment =
                    fallback: "Here you go, have #{data.randomWinner.userLink}'s parking space!"
                    text: "Here you go, have #{data.randomWinner.userLink}'s parking space!"
                    color: 'good'

                replyWithAttachments =
                    attachments: [attachment]
                    timestamp: message.ts

                if text
                    replyWithAttachments.text = text

                bot.reply message, replyWithAttachments

    controller.hears ['\\bjoin\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        data = {}

        getUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        addUserIfNotAdded = (next) ->
            if data.user?.status is 'ACTIVE'
                return next null

            bot.api.users.info
                user: message.user
            , (err, response) ->
                if err
                    return next err

                controller.storage.users.save
                    id: data.user?.id or message.user
                    status: 'ACTIVE'
                    username: data.user?.username or response.user.name
                    realName: data.user?.realName or response.user.real_name
                    userLink: data.user?.userLink or "<@#{message.user}|#{response.user.name}>"
                    recentWins: data.user?.recentWins or []
                , (err) ->
                    if err
                        return next err

                    next null

        async.waterfall [
            getUser
            addUserIfNotAdded
        ], (err) ->
            if err
                bot.botkit.log('Failed to add user to parking lottery.', err)
            else
                if data.user?.status is 'ACTIVE'
                    attachment =
                        fallback: "You've already joined the Parking Lottery!"
                        text: "You've already joined the Parking Lottery!"
                        color: 'warning'

                    emoji = 'suspect'
                else if data.user?.status is 'INACTIVE'
                    text = "*Welcome back to the Parking Lottery <@#{message.user}>!*"
                    attachment =
                        fallback: "You'll be automatically entered to win a parking space every week."
                        text: "You'll be automatically entered to win a parking space every week."
                        color: 'good'

                    emoji = 'sunglasses'
                else
                    text = "*Welcome to the Parking Lottery <@#{message.user}>!*"
                    attachment =
                        fallback: "You'll be automatically entered to win a parking space every week."
                        text: "You'll be automatically entered to win a parking space every week."
                        color: 'good'

                    emoji = '+1::skin-tone-2'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    timestamp: message.ts

                if text
                    replyWithAttachments.text = text

                bot.reply message, replyWithAttachments

    controller.hears ['\\bleave\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        data = {}

        getUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        updateUserIfExists = (next) ->
            if !data.user
                return next null

            if data.user.status is 'INACTIVE'
                attachment =
                    fallback: "You've already been removed from the Parking Lottery!"
                    text: "You've already been removed from the Parking Lottery!"
                    color: 'warning'

                emoji = 'angry'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    timestamp: message.ts

                bot.reply message, replyWithAttachments

                return next new Error 'User already removed from parking lottery.'

            newUser = _.clone(data.user)
            newUser.status = 'INACTIVE'
            controller.storage.users.save newUser, (err) ->
                if err
                    return next err

                next null

        async.waterfall [
            getUser
            updateUserIfExists
        ], (err) ->
            if err
                bot.botkit.log('Failed to remove user from parking lottery.', err)
            else
                if !data.user
                    attachment =
                        fallback: "You haven't even joined the Parking Lottery yet!"
                        text: "You haven't even joined the Parking Lottery yet!"
                        color: 'warning'

                    emoji = 'confused'
                else
                    text = "*<@#{message.user}>, you've just left the Parking Lottery!*"
                    attachment =
                        fallback: "You'll need to re-join if you want to win a parking space again."
                        text: "You'll need to re-join if you want to win a parking space again."
                        color: 'good'

                    emoji = 'cry'

                bot.api.reactions.add
                    timestamp: message.ts
                    channel: message.channel
                    name: emoji
                , (err, response) ->
                    if err
                        bot.botkit.log('Failed to add emoji reaction.', err)

                replyWithAttachments =
                    attachments: [attachment]
                    timestamp: message.ts

                if text
                    replyWithAttachments.text = text

                bot.reply message, replyWithAttachments

    controller.hears ['\\blast\\b', '\\bprevious\\b', '\\blast week\\b', '\\bprevious week\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        {previousWeek, previousYear} = getPreviousWeekDates()

        getWinners previousWeek, previousYear, (err, previousWinners) ->
            if err
                bot.botkit.log('Error getting users.', err)

            if previousWinners.length
                text = "*Previous weeks Parking Lottery winners was:*"
                attachment =
                    fallback: "#{previousWinners.join(', ')}."
                    text: "#{previousWinners.join(', ')}."
                    color: 'good'
            else
                attachment =
                    fallback: "I don't have any data for the previous weeks winners."
                    title: "Error"
                    text: "I don't have any data for the previous weeks winners."
                    color: 'danger'

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments


    controller.hears ['\\bcurrent\\b', '\\bcurrent week\\b', '\\bthis week\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        {currentWeek, currentYear} = getCurrentWeekDates()

        getWinners currentWeek, currentYear, (err, currentWinners) ->
            if err
                bot.botkit.log('Error getting users.', err)

            if currentWinners.length
                text = "*Current weeks Parking Lottery winners are:*"
                attachment =
                    fallback: "#{currentWinners.join(', ')}."
                    text: "#{currentWinners.join(', ')}."
                    color: 'good'
            else
                attachment =
                    fallback: "I don't have any data for this weeks winners."
                    title: "Error"
                    text: "I don't have any data for this weeks winners."
                    color: 'danger'

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments

    controller.hears ['\\bnext\\b', '\\bnext week\\b', '\\bupcoming\\b', '\\bupcoming week\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        {nextWeek, nextYear} = getNextWeekDates()

        getWinners nextWeek, nextYear, (err, upcomingWinners) ->
            if err
                bot.botkit.log('Error getting users.', err)

            if upcomingWinners.length
                text = "*Upcoming weeks Parking Lottery winners are:*"
                attachment =
                    fallback: "#{upcomingWinners.join(', ')}."
                    text: "#{upcomingWinners.join(', ')}."
                    color: 'good'
            else
                attachment =
                    fallback: "I don't have any data for the upcoming weeks winners, this could be because the winners haven't been drawn yet!"
                    title: "Error"
                    text: "I don't have any data for the upcoming weeks winners, this could be because the winners haven't been drawn yet!"
                    color: 'danger'

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments

    controller.hears ['\\blist\\b', '\\busers\\b'], 'direct_message,direct_mention,mention', (bot, message) ->
        controller.storage.users.all (err, users) ->
            if err
                bot.botkit.log('Error getting users.', err)

            activeUsers = _(users)
                .chain()
                .filter (user) ->
                    user.status is 'ACTIVE'
                .pluck('username')
                .value()

            if activeUsers.length
                text = "*There's #{activeUsers.length} #{if activeUsers.length isnt 1 then 'people' else 'person'} in the draw for the Parking Lottery.*"
                attachment =
                    fallback: "#{activeUsers.join(', ')}."
                    text: "#{activeUsers.join(', ')}."
                    color: 'good'
            else
                attachment =
                    fallback: "I don't have any data of people in the draw."
                    title: "Error"
                    text: "I don't have any data of people in the draw."
                    color: 'danger'

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments

    controller.hears ['\\bdonate\\b'], 'direct_mention,mention', (bot, message) ->
        data = {}

        getDonator = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        doesUserHaveParkingSpotToDonate = (next) ->
            if !data.user
                return next new Error 'No user data.'

            {currentWeek, currentYear} = getCurrentWeekDates()
            {nextWeek, nextYear} = getNextWeekDates()

            data.currentWeekWinner = _(data.user.recentWins)
                .chain()
                .findWhere({week: currentWeek, year: currentYear})
                .clone()
                .value()

            data.nextWeekWinner = _(data.user.recentWins)
                .chain()
                .findWhere({week: nextWeek, year: nextYear})
                .clone()
                .value()

            if (!data.currentWeekWinner or data.currentWeekWinner?.donated) and (!data.nextWeekWinner or data.nextWeekWinner?.donated)
                return next new Error 'No wins on user that can be donated!'
                
            next null

        getEligibleUsers = (next) ->
            controller.storage.users.all (err, users) ->
                if err
                    return next err

                data.eligibleUsers = _(users)
                    .chain()
                    .clone()
                    .filter (user) ->
                        # Users can decide to leave the parking lottery
                        if user.status isnt 'ACTIVE'
                            return false

                        if !user.recentWins.length
                            return true
                        else
                            if data.currentWeekWinner and !data.currentWeekWinner.donated
                                {previousWeek, previousYear} = getCurrentWeekDates()
                                {currentWeek, currentYear} = getCurrentWeekDates()

                                data.previousWeek = previousWeek
                                data.previousYear = previousYear
                                data.week = currentWeek
                                data.year = currentYear
                            else if data.nextWeekWinner and !data.nextWeekWinner.donated
                                {currentWeek, currentYear} = getCurrentWeekDates()
                                {nextWeek, nextYear} = getNextWeekDates()

                                data.previousWeek = currentWeek
                                data.previousYear = currentYear
                                data.week = nextWeek
                                data.year = nextYear

                            if _(user.recentWins).findWhere({week: data.previousWeek, year: data.previousYear})
                                return false

                            if _(user.recentWins).findWhere({week: data.week, year: data.year})
                                return false

                            return true
                    .value()

                next null

        drawDonationUser = (next) ->
            if !data.eligibleUsers.length
                return next new Error 'No eligible users!'

            data.winner = _.sample(data.eligibleUsers, 1)?[0]
            next null

        setDonatedFlagOnDonatorWin = (next) ->
            newUser = _.clone(data.user)
            winToUpdate = _(newUser.recentWins).findWhere({week: data.week, year: data.year})
            winIndex = _.indexOf(newUser.recentWins, winToUpdate)
            newUser.recentWins[winIndex].donated = data.winner.id

            controller.storage.users.save newUser, (err) ->
                if err
                    bot.botkit.log('Error while updating win on user.', err)

                next null

        saveWinOnUser = (next) ->
            newUser = _.clone(data.winner)
            newUser.recentWins.push {week: data.week, year: data.year, donated: true}
            controller.storage.users.save newUser, (err) ->
                if err
                    bot.botkit.log('Error while saving win on users.', err)
                    # TODO: remove donated flag on user donating win as unable to save win on user

                next null

        async.waterfall [
            getDonator
            doesUserHaveParkingSpotToDonate
            getEligibleUsers
            drawDonationUser
            setDonatedFlagOnDonatorWin
            saveWinOnUser
        ], (err) ->
            if err
                bot.botkit.log('Failed to draw winners.', err)

                if !data.user or (!data.currentWeekWinner and !data.nextWeekWinner)
                    attachment =
                        fallback: "<@#{message.user}>: You don't have any wins to donate!"
                        text: "<@#{message.user}>: You don't have any wins to donate!"
                        color: 'warning'

                    emoji = 'suspect'
            else
                if data.currentWeekWinner and !data.currentWeekWinner.donated
                    week = "this"
                else if data.nextWeekWinner and !data.nextWeekWinner.donated
                    week = "next"

                text = "<!channel> Hello all! <@#{message.user}> just donated their parking space for #{week} week...."
                attachment =
                    fallback: "...and the lucky winner is...\n#{data.winner.userLink}."
                    title: "And the lucky winner is"
                    text: "#{data.winner.userLink}."
                    color: 'good'

                emoji = '+1::skin-tone-2'

            bot.api.reactions.add
                timestamp: message.ts
                channel: message.channel
                name: emoji

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments

    controller.hears ['\\bdraw\\b'], 'direct_mention,mention', (bot, message) ->
        {nextWeek, nextYear} = getNextWeekDates()

        data = {}
        data.alreadyDrawn = false

        getCallerUser = (next) ->
            controller.storage.users.get message.user, (err, user) ->
                if err
                    bot.botkit.log('Failed to get user data.', err)

                data.user = user
                next null

        maybeGetCallerUserFromSlack = (next) ->
            if data.user
                return next null

            bot.api.users.info
                user: message.user
            , (err, response) ->
                if err
                    return next err

                data.user =
                    id: message.user
                    username: response.user.name
                    realName: response.user.real_name
                    userLink: "<@#{message.user}|#{response.user.name}>"

                next null

        checkCallerIsAdmin = (next) ->
            if data.user.username not in config.admins
                return next new Error 'Not admin user!'

            next null

        checkIfDrawIsRequired = (next) ->
            controller.storage.teams.get message.team, (err, team) ->
                if err
                    bot.botkit.log('Failed to get team data.', err)

                if !team
                    return next null

                if _(team.draws).findWhere({week: nextWeek, year: nextYear})
                    bot.botkit.log('Winners have already been drawn for next week.')
                    data.alreadyDrawn = true
                    return next new Error 'Winners have already been drawn for next week.'

                next null

        drawWinners = (next) ->
            draw message, (err, winners) ->
                if err
                    return next err

                data.winners = winners
                next null

        saveDrawOnTeam = (next) ->
            saveDraw message, (err) ->
                if err
                    return next err

                next null

        async.waterfall [
            getCallerUser
            maybeGetCallerUserFromSlack
            checkCallerIsAdmin
            checkIfDrawIsRequired
            drawWinners
            saveDrawOnTeam
        ], (err) ->
            if err
                bot.botkit.log('Failed to draw winners.', err)

                if data.user.username not in config.admins
                    attachment =
                        fallback: "<@#{message.user}>: You're not an admin!"
                        text: "<@#{message.user}>: You're not an admin!"
                        color: 'danger'

                    emoji = 'suspect'
                else if data.alreadyDrawn is true
                    attachment =
                        fallback: "The upcoming Parking Lottery winners have already been drawn!"
                        text: "The upcoming Parking Lottery winners have already been drawn!"
                        color: 'warning'

                    emoji = 'grey_exclamation'
                else
                    attachment =
                        fallback: "<@#{message.user}>: I couldn't draw any winners, please try again."
                        title: "Error"
                        text: "<@#{message.user}>: I couldn't draw any winners, please try again."
                        color: 'danger'

                    emoji = 'exclamation'
            else
                text = "<!channel> Hello all! I would like to announce our parking space winners for this coming week...."
                # If draw winners images are set randomly pick one to post
                if config.drawWinnersImages.length
                    image = _.sample(config.drawWinnersImages, 1)?[0]

                    text += "\n#{image}"

                    attachment =
                        fallback: "...and the winners are...\n#{data.winners.join(', ')}."
                        text: "#{data.winners.join(', ')}."
                        #image_url: image
                        color: 'good'
                else
                    attachment =
                        fallback: "...and the winners are...\n#{data.winners.join(', ')}."
                        title: "Upcoming weeks winners of the Parking Lottery"
                        text: "#{data.winners.join(', ')}."
                        color: 'good'

                emoji = 'admission_tickets'

            bot.api.reactions.add
                timestamp: message.ts
                channel: message.channel
                name: emoji

            replyWithAttachments =
                attachments: [attachment]
                timestamp: message.ts

            if text
                replyWithAttachments.text = text

            bot.reply message, replyWithAttachments

draw = (message, cb) ->
    {nextWeek, nextYear} = getNextWeekDates()

    data = {}

    getEligibleUsers = (next) ->
        controller.storage.users.all (err, users) ->
            if err
                return next err

            data.eligibleUsers = _(users)
                .chain()
                .clone()
                .filter (user) ->
                    # Users can decide to leave the parking lottery
                    if user.status isnt 'ACTIVE'
                        return false

                    if !user.recentWins.length
                        return true
                    else
                        async.eachSeries _.range(config.weeksBetweenWins), (week, cb) ->
                            {weekInPast, yearInPast} = getWeekDatesInPast(week)

                            if _(user.recentWins).findWhere({week: weekInPast, year: yearInPast})
                                return cb new Error 'User recently won.'

                            cb null

                        , (err) ->
                            if err
                                bot.botkit.log('User not eligible.', err)
                                return false

                            return true
                .value()

            next null

    drawWinners = (next) ->
        if !data.eligibleUsers.length
            return next new Error 'No eligible users!'

        data.winners = _.sample(data.eligibleUsers, config.parkingSpaces)
        next null

    saveWinsOnUsers = (next) ->
        async.eachSeries data.winners, (user, cb) ->
            newUser = _.clone(user)
            newUser.recentWins.push {week: nextWeek, year: nextYear}
            controller.storage.users.save newUser, (err) ->
                if err
                    return cb err

                cb null
        , (err) ->
            if err
                bot.botkit.log('Error while saving wins on users.', err)

            next null

    async.waterfall [
        getEligibleUsers
        drawWinners
        saveWinsOnUsers
    ], (err) ->
        if err
            cb err
        else
            cb null, _(data.winners).pluck('userLink')

saveDraw = (message, cb) ->
    {nextWeek, nextYear} = getNextWeekDates()

    data = {}

    getTeamData = (next) ->
        controller.storage.teams.get message.team, (err, team) ->
            if err
                bot.botkit.log('Failed to get team data.', err)

            data.team = team
            next null

    saveDrawOnTeam = (next) ->
        if data.team
            newTeamData = _.clone(data.team)
        else
            newTeamData =
                id: message.team
                draws: []

        newTeamData.draws.push {week: nextWeek, year: nextYear}

        controller.storage.teams.save newTeamData, (err) ->
            if err
                bot.botkit.log('Error while saving draw on team.', err)

            next null

    async.waterfall [
        getTeamData
        saveDrawOnTeam
    ], (err) ->
        if err
            cb err
        else
            cb null

getWinners = (week, year, cb) ->
    controller.storage.users.all (err, users) ->
        if err
            bot.botkit.log('Error getting users.', err)

        winners = _(users)
            .chain()
            .filter (user) ->
                recentWin = _(user.recentWins).findWhere({week: week, year: year})
                recentWin and recentWin.donated isnt true
            .map (user) ->
                recentWin = _(user.recentWins).findWhere({week: week, year: year})
                if recentWin.donated
                    donatedWinUser = _(users).findWhere({id: recentWin.donated})
                    return "#{donatedWinUser.userLink} donated by: #{user.userLink}"
                else
                    return user.userLink
            .value()

        cb null, winners

getWeekDatesInPast = (weeks) ->
    return {
        weekInPast: moment().subtract(weeks, 'week').week()
        yearInPast: moment().subtract(weeks, 'week').year()
    }

getPreviousWeekDates = ->
    previousWeekDates = getWeekDatesInPast(1)

    return {
        previousWeek: previousWeekDates.weekInPast
        previousYear: previousWeekDates.yearInPast
    }

getCurrentWeekDates = ->
    return {
        currentWeek: moment().week()
        currentYear: moment().year()
    }

getNextWeekDates = ->
    return {
        nextWeek: moment().add(1, 'week').week()
        nextYear: moment().add(1, 'week').year()
    }
