fs = require 'fs'
os = require 'os'
path = require 'path'
readline = require 'readline'
util = require 'util'
GitHub = require 'github-base'

## Options
optionsFilename = path.join os.homedir(), '.gitall.json'
optionsText = fs.readFileSync optionsFilename, encoding: 'utf8'
options = JSON.parse optionsText
stringify = (data) -> JSON.stringify(data, null, 2) + '\n'
  # https://github.com/npm/init-package-json/blob/latest/init-package-json.js#L106

## Defaults
options.orgs ?= {}

## Option interpretation
host2apiurl = (host) ->
  if host == 'github.com'
    "https://api.#{host}/"
  else
    "https://#{host}/api/v3/"

## Interactivity
rl = readline.createInterface
  input: process.stdin
  output: process.stdout
ask = (question, defaultAnswer) ->
  new Promise (resolve) ->
    rl.question "#{question} [#{defaultAnswer}] ", (answer) ->
      answer = defaultAnswer if answer == ''
      resolve answer
askLetter = (question, defaultAnswer, letters) ->
  loop
    answer = await ask question, defaultAnswer
    letter = answer[0].toLowerCase()
    if letter in letters
      return letter

## Code
syncOrgs = ->
  for account in options.accounts
    github = new GitHub
      apiurl: host2apiurl account.host
      token: account.token
    console.log 'request'
    result = await github.request 'GET', 'user/orgs'
    orgs = result.body
    for org in orgs
      if org.login not of options.orgs
        console.log "NEW ORGANIZATION: #{org.login}"
        answer = await askLetter \
          "Add this organization? (yes/no/quit/forget)", "no", "ynqf"
        switch answer
          when 'y'
            console.log org
            dir = await ask "Directory for organization:", "~"
            options.orgs[org.login] =
              dir: dir
          when 'f'
            options.orgs[org.login] =
              forget: true
          when 'q'
            return
          #when 'n'

sync = ->
  await syncOrgs()
  if (s = stringify options) != optionsText
    console.log
    console.log s
    answer = await askLetter \
      "Save changes to #{path.basename optionsFilename}? (yes/no)", "no", "yn"
    if answer == 'y'
      await util.promisify(fs.writeFile) optionsFilename, s

sync().then -> process.exit()
