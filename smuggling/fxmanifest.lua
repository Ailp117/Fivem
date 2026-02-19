fx_version 'cerulean'
game 'gta5'

description 'GTA Online Style Hangar Smuggling System für QBCore'
author 'DeinName'
version '2.0.0'

shared_scripts {
    '@qb-core/shared/locale.lua',
    '@ox_lib/init.lua'
}

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

dependencies {
    'qb-core',
    'ox_lib',
    'oxmysql'
}