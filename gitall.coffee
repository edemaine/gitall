`#!/usr/bin/env node
`
child_process = require 'child_process'
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

expandTilde = (dir) ->
  dir.replace /^~([\/\\]|$)/, (match, end) -> os.homedir() + end
shrinkTilde = (dir) ->
  home = os.homedir()
  if dir[...home.length] == home
    "~" + dir[home.length..]
  else
    dir
isDir = (dir) ->
  try
    stat = await util.promisify(fs.stat) expandTilde dir
  catch e
    return null
  stat.isDirectory()

## Interactivity
rl = null
rlReject = null
ask = (question, defaultAnswer) ->
  unless rl?
    rl = readline.createInterface
      input: process.stdin
      output: process.stdout
    rl.on 'close', (error) ->
      console.log()
      rl = null
      rlReject 'Ctrl-C'
  new Promise (resolve, reject) ->
    rlReject = reject
    rl.question "#{question} [#{defaultAnswer}] ", (answer) ->
      answer = defaultAnswer if answer == ''
      resolve answer
askLetter = (question, defaultAnswer, letters) ->
  loop
    answer = await ask question, defaultAnswer
    letter = answer[0].toLowerCase()
    if letter in letters
      return letter

runOK = (spawnOut) ->
  if spawnOut.status != 0
    console.log "> git failed"
    answer = await askLetter "Continue? (yes/no)", "no", "yn"
    if answer == 'n'
      throw "> Aborting"

## Code
syncOrgs = (github) ->
  result = await github.get 'user/orgs'
  orgs = result.body
  lastDirRoot = '~'
  for org in orgs
    if org.login not of options.orgs
      console.log()
      console.log "** NEW ORGANIZATION: #{org.login}"
      answer = await askLetter \
        "Add this organization? (yes/no/quit/forget)", "no", "ynqf"
      switch answer
        when 'y'
          loop
            dir = await ask "Directory for organization:",
              "#{lastDirRoot}/#{org.login}"
            switch await isDir dir
              when true
                useDir = await askLetter \
                  "> Directory exists; add repositories to this directory?",
                  "no", "yn"
                continue if useDir == 'n'
              when false
                console.log "> That's an existing file, not a directory."
                continue
            break
          options.orgs[org.login] =
            dir: dir
          lastDirRoot = path.dirname dir
        when 'f'
          options.orgs[org.login] =
            forget: true
        when 'q'
          return
        #when 'n'

syncRepos = (github) ->
  for org, orgOptions of options.orgs
    continue if orgOptions.forget
    console.log()
    console.log "** ORGANIZATION: #{org}"
    unless orgOptions.dir?
      console.log "> No directory information available! Add 'dir' field."
      continue
    result = await github.get "orgs/#{org}/repos"
    repos = result.body
    for repo in repos
      repoDir = path.join expandTilde(orgOptions.dir), repo.name
      remote = repo.ssh_url
      switch await isDir repoDir
        when false
          console.log "> Repo '#{repo.full_name}' BLOCKED by file '#{repoDir}'"
          continue
        when true
          git = child_process.spawnSync 'git',
            ['remote', 'get-url', 'origin'],
            cwd: repoDir
          if "not a git repository" in git.stderr.toString 'ascii'
            console.log "> Repo '#{repo.full_name}' BLOCKED by non-git directory '#{repoDir}'"
            continue
          origin = git.stdout.toString 'ascii'
          .replace /\n$/, ''
          if origin != remote
            console.log \
              "> Git repo #{shrinkTilde repoDir} has origin set to #{origin}"
            answer = await askLetter \
              "Set remote to #{remote}? (yes/no)", 'no', 'yn'
            if answer == 'y'
              await runOK child_process.spawnSync 'git',
                ['remote', 'set-url', 'origin', remote],
                cwd: repoDir
                stdio: 'inherit'
        when null
          await runOK child_process.spawnSync 'git',
            ['clone', remote, repoDir],
            stdio: 'inherit'

      if process.argv.length > 2
        console.log "#{shrinkTilde repoDir}$ git #{process.argv[2..].join ' '}"
        await runOK child_process.spawnSync 'git', process.argv[2..],
          cwd: repoDir
          stdio: 'inherit'

allAccounts = (todo) ->
  for account in options.accounts
    github = new GitHub
      apiurl: host2apiurl account.host
      token: account.token
    await todo github

syncAccounts = ->
  try
    await allAccounts syncOrgs
  catch e
    if e == "Ctrl-C"
      return await saveOptions()
    else
      throw e
  await saveOptions()
  await allAccounts syncRepos

saveOptions = ->
  return unless options? and optionsText?
  if (s = stringify options) != optionsText
    console.log()
    console.log s
    try
      answer = await askLetter \
        "Save changes to #{path.basename optionsFilename}? (yes/no)", "no", "yn"
    catch e
      if e == "Ctrl-C"
        return
      else
        throw e
    if answer == 'y'
      await util.promisify(fs.writeFile) optionsFilename, s

syncAccounts().then ->
  rl?.close()
,
  (e) ->
    console.log e.toString()
    rl?.close()
