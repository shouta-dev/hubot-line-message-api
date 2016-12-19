try
    {Robot,Adapter,TextMessage,User} = require "hubot"
catch
    prequire = require "parent-require"
    {Robot,Adapter,TextMessage,User} = prequire "hubot"
request = require "request"
pushEP = "https://api.line.me/v2/bot/message/push"
replyEP = "https://api.line.me/v2/bot/message/reply"
getContentEP = "https://api.line.me/v2/bot/message/%s/content"
getProfileEP = "https://api.line.me/v2/bot/profile/%s"

class LineMessageApiAdapter extends Adapter
    data: {}
    run: ->
        @endpoint = process.env.HUBOT_ENDPOINT ? "/hubot/incoming"
        @channelAccessToken = process.env.LINE_CHANNEL_ACCESS_TOKEN ? ""
        unless @channelAccessToken?
            @robot.logger.emergency "LINE_CHANNEL_ACCESS_TOKEN is required"
            process.exit 1
        @robot.router.post @endpoint, (req, res) =>
            console.log "callback body: #{JSON.stringify(req.body)}"
            # TODO: validate signeture
            events = req.body.events
            for event in events
                {replyToken, type, source, message, postback} = event
                switch source.type
                    when "user"
                        from = source.userId
                    when "group"
                        from = source.groupId
                    when "room"
                        from = source.roomId

                user = LineUser.init(@robot, from, replyToken)
                console.log "from: #{source.type} => #{from}"                
                if event.type == "message"
                    switch message.type
                        when "text"
                            text = message.text ? ""
                            console.log "text: #{text}"
                            @receive new TextMessage(user, text, message.id)
                        when "image"
                            text = ""
                            @receive new ImageMessage(user, text, message.id)
                        when "sticker"
                            text = ""
                            @receive new StickerMessage(user, text, message.id)
                        else
                            # TODO: text, image以外の処理
                            console.log "This message type is not supported.(#{message.type})"
                else if event.type == "postback"
                    console.log "postback.data: #{postback.data}"
                    text = ""
                    messageId = 0
                    @receive new PostbackMessage(user, text, messageId, postback.data)
                else if event.type == "follow"
                    console.log "follow"
                    console.log(event)
                    @receive new FollowMessage(user)
            @emit "connected"

    send: (envelope, strings...) ->
        @_updateDataForPush(envelope)
        this._postToLine(pushEP, envelope, strings...)

    reply: (envelope, strings...) ->
        @_updateDataForReply(envelope)
        this._postToLine(replyEP, envelope, strings...)

    _postToLine: (url, envelope, strings...) ->
        for string in strings
            switch string.type
                when "text"
                    @updateDataForReplyText(string, @data)
                when "image", "video"
                    @updateDataForReplyImageVideo(string, @data)
                when "audio"
                    @updateDataForReplyAudio(string, @data)
                when "location"
                    @updateDataForReplyLocation(string, @data)
                when "sticker"
                    @updateDataForReplySticker(string, @data)
                when "buttons"
                    @updateDataForReplyButtons(string, @data)
                when "carousel"
                    @updateDataForReplyCarousel(string, @data)
                when "confirm"
                    @updateDataForReplyConfirm(string, @data)
                else
                    @robot.logger.emergency "Unrecognized type #{string.type}"
                    process.exit 1
        console.log @data
        request
            url: url
            headers:
                "Content-Type": "application/json"
                "Authorization": "Bearer #{@channelAccessToken}"
            method: "POST"
            proxy: process.env.FIXIE_URL ? ""
            body: JSON.stringify(@data),
            (err, response, body) ->
                throw err if err
                if response.statusCode is 200
                  console.log "success"
                  console.log body
                else
                  console.log "response error: #{response.statusCode}"
                  console.log body

    _updateDataForReply: (envelope) ->
        replyToken = envelope.user.replyToken
        @data =
            replyToken: replyToken
            messages: []

    _updateDataForPush: (envelope) ->
        to = envelope.user.id
        to = envelope.user.pushId if envelope.user.pushId?

        @data =
            to: to
            messages: []

    updateDataForReplyText: (string, data) ->
        for content in string.contents
            data.messages.push
                type: "text"
                text: content

    updateDataForReplyImageVideo: (string, data) ->
        for content in string.contents
            data.messages.push
                type: string.type
                originalContentUrl: content.original
                previewImageUrl: content.preview

    updateDataForReplyAudio: (string, data) ->
        for content in string.contents
            data.messages.push
                type: string.type
                originalContentUrl: content.original
                # TODO: validation number
                duration: content.duration

    updateDataForReplyLocation: (string, data) ->
        for content in string.contents
            data.messages.push
                type: "location"
                title: content.title
                address: content.address
                # TODO: validation number
                latitude: content.latitude
                longitude: content.longitude

    updateDataForReplySticker: (string, data) ->
        for content in string.contents
            data.messages.push
                type: string.type
                packageId: content.package
                sticker: content.sticker

    updateDataForReplyButtons: (string, data) ->
        for content in string.contents
            data.messages.push
                type: "template"
                altText: string.altText ? "Hello Line Bot"
                template:
                    type: "buttons"
                    thumbnailImageUrl: content.image
                    title: content.title
                    text: content.text
                    actions: content.actions

    updateDataForReplyCarousel: (string, data) ->
        columns = []
        for content in string.contents
            columns.push
                thumbnailImageUrl: content.image
                title: content.title
                text: content.text
                actions: content.actions
        data.messages.push
            type: "template"
            altText: string.altText ? "Hello Line Bot"
            template:
                type: "carousel"
                columns: columns

    updateDataForReplyConfirm: (string, data) ->
        for content in string.contents
            data.messages.push
                type: "template"
                altText: string.altText ? "Hello Line Bot"
                template:
                    type: "confirm"
                    text: content.text
                    actions: content.actions

class LineUser
    @init: (robot, from, replyToken) ->
        user = robot.brain.userForId from
        user.replyToken = replyToken
        user.getProfile = (callback) ->
            @channelAccessToken = process.env.LINE_CHANNEL_ACCESS_TOKEN ? ""
            url = getProfileEP.replace('%s', from)
            console.log("url:#{url}")
            request
                url: url
                headers:
                    "Content-Type": "application/json"
                    "Authorization": "Bearer #{@channelAccessToken}"
                method: "GET"
                proxy: process.env.FIXIE_URL ? ""
                encoding: 'utf-8'
                (err, response, body) ->
                    throw err if err
                    if response.statusCode is 200
                      console.log "GetProfile success"
                      body = JSON.parse(body)
                      user.name = body.displayName
                      user.displayName = body.displayName
                      if body.pictureUrl?
                        user.pictureUrl = body.pictureUrl.replace(/^http/i, 'https')
                      user.statusMessage = body.statusMessage
                      callback(user, body)
                    else
                      console.log "response error: #{response.statusCode}"
                      console.log body
        return user

class PostbackMessage extends TextMessage
    constructor: (@user, @text, @id, @data) ->
        super @user, @text, @id

class FollowMessage extends TextMessage
    constructor: (@user) ->
        super @user, "", 0

class StickerMessage extends TextMessage
    constructor: (@user) ->
        super @user, "", 0

class ContentMessage extends TextMessage
    getContent: (callback) ->
        messageId = this.id
        @channelAccessToken = process.env.LINE_CHANNEL_ACCESS_TOKEN ? ""
        url = getContentEP.replace('%s', messageId)
        request
            url: url
            headers:
                "Content-Type": "application/json"
                "Authorization": "Bearer #{@channelAccessToken}"
            method: "GET"
            proxy: process.env.FIXIE_URL ? ""
            encoding: null
            (err, response, body) ->
                throw err if err
                if response.statusCode is 200
                  console.log "success"
                  callback(body)
                else
                  console.log "response error: #{response.statusCode}"
                  console.log body

class ImageMessage extends ContentMessage

exports.use = (robot) ->
    new LineMessageApiAdapter(robot)
exports.ImageMessage = ImageMessage
exports.PostbackMessage = PostbackMessage
exports.FollowMessage = FollowMessage
exports.StickerMessage = StickerMessage
