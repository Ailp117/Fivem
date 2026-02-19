fx_version 'cerulean'
game 'gta5'

description 'GTA Online Style Hangar Smuggling System für ESX'
author 'DeinName'
version '2.0.0'

shared_scripts {
    '@es_extended/imports.lua',
    'shared/config.lua',
    '@ox_lib/init.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'ox_inventory',
    'ox_target',
    'oxmysql'
}
