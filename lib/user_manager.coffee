PBError = require('user-error')

config = require('./config')

module.exports = class UserManager

    UserManager.new = (configuration) -> new UserManager configuration

    constructor: (configuration) ->
        throw new Error 'controller is null or undefined' if not configuration?.controller?
        throw new Error 'bot is null or undefined' if not configuration?.bot?

        @controller = configuration.controller
        @bot = configuration.bot

    getLocalUser: (opts, cb) ->
        @controller.storage.users.get opts.user, (err, user) ->
            if err
                return cb new PBError('Failed to get local user data.', {cause: err})

            cb null, user
            
    getLocalUsers: (opts, cb) ->
        @controller.storage.users.all (err, users) ->
            cb err, users

    getSlackUser: (opts, cb) ->
        @bot.api.users.info
            user: opts.user
        , (err, response) =>
            if err
                @bot.botkit.log('Failed to get user data from slack.', err)
                return cb new PBError('Failed to get user data from slack.', {cause: err})

            user =
                id: opts.user
                username: response.user.name
                realName: response.user.real_name
                userLink: "<@#{opts.user}|#{response.user.name}>"

            cb null, user

    isUserAdmin: (opts) ->
        opts.username in config.admins

    saveUser: (opts, cb) ->
        @controller.storage.users.save
            id: opts.user
            status: opts.status
            username: opts.username
            realName: opts.realName
            userLink: opts.userLink
            reg: opts.reg
            recentWins: opts.recentWins
        , (err) ->
            cb err

    addUserFromSlack: (opts, cb) ->
        data = {}

        getSlackUser = (next) =>
            @getSlackUser {user: opts.user}, (err, user) ->
                if err
                    return next err

                if !err and !user
                    return next new PBError('No slack user.', {code: 'NO_SLACK_USER'})

                data.user = user

        saveUser = (next) =>
            @controller.storage.users.save
                id: opts.user
                status: 'ACTIVE'
                username: data.user.name
                realName: data.user.real_name
                userLink: "<@#{opts.user}|#{data.user.name}>"
                reg: opts.reg
                recentWins: []
            , (err) ->
                if err
                    return next err

                next null

        async.waterfall [
            getSlackUser
            saveUser
        ], (err) ->
            cb err
            

    getWinners: (week, year, cb) ->
        @getLocalUsers (err, users) ->
            if err
                @bot.botkit.log('Error getting users.', err)

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
