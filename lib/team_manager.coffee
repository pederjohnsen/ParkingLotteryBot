PBError = require('user-error')

module.exports = class TeamManager

    TeamManager.new = (configuration) -> new TeamManager configuration

    constructor: (configuration) ->
        throw new Error 'controller is null or undefined' if not configuration?.controller?
        throw new Error 'bot is null or undefined' if not configuration?.bot?

        @controller = configuration.controller
        @bot = configuration.bot

    getLocalTeam: (opts, cb) ->
        @controller.storage.teams.get opts.team, (err, team) ->
            if err
                return cb new PBError('Failed to get local team data.', {cause: err})

            cb null, user

    saveTeam: (opts, cb) ->
        @controller.storage.teams.save opts, cb
