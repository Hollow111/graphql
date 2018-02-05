#!/usr/bin/env tarantool

local fio = require('fio')

-- require in-repo version of graphql/ sources despite current working directory
package.path = fio.abspath(debug.getinfo(1).source:match("@?(.*/)")
    :gsub('/./', '/'):gsub('/+$', '')) .. '/../../?.lua' .. ';' ..
    package.path

local json = require('json')
local yaml = require('yaml')
local graphql = require('graphql')
local utils = require('graphql.utils')

local schemas = json.decode([[{
    "user": {
        "type": "record",
        "name": "user",
        "fields": [
            { "name": "user_id", "type": "string" },
            { "name": "first_name", "type": "string" },
            { "name": "last_name", "type": "string" }
        ]
    },
    "order": {
        "type": "record",
        "name": "order",
        "fields": [
            { "name": "order_id", "type": "string" },
            { "name": "user_id", "type": "string" },
            { "name": "description", "type": "string" }
        ]
    }
}]])

local collections = json.decode([[{
    "user_collection": {
        "schema_name": "user",
        "connections": [
            {
                "type": "1:N",
                "name": "order_connection",
                "destination_collection":  "order_collection",
                "parts": [
                    { "source_field": "user_id", "destination_field": "user_id" }
                ],
                "index_name": "user_id_index"
            }
        ]
    },
    "order_collection": {
        "schema_name": "order",
        "connections": [
            {
                "type": "1:1",
                "name": "user_connection",
                "destination_collection":  "user_collection",
                "parts": [
                    { "source_field": "user_id", "destination_field": "user_id" }
                ],
                "index_name": "user_id_index"
            }
        ]
    }
}]])

local service_fields = {
    user = {
        {name = 'expires_on', type = 'long', default = 0},
    },
    order = {},
}

local indexes = {
    user_collection = {
        user_id_index = {
            service_fields = {},
            fields = {'user_id'},
            index_type = 'tree',
            unique = true,
        },
    },
    order_collection = {
        order_id_index = {
            service_fields = {},
            fields = {'order_id'},
            index_type = 'tree',
            unique = true,
        },
        user_id_index = {
            service_fields = {},
            fields = {'user_id'},
            index_type = 'tree',
            unique = false,
        },
    },
}

-- fill spaces
-- -----------

-- user_collection fields
local U_USER_ID_FN = 2

-- order_collection fields
local O_ORDER_ID_FN = 1
local O_USER_ID_FN = 2

box.cfg{background = false}
box.once('test_space_init_spaces', function()
    box.schema.create_space('user_collection')
    box.space.user_collection:create_index('user_id_index',
        {type = 'tree', unique = true, parts = {
            U_USER_ID_FN, 'string'
        }}
    )
    box.schema.create_space('order_collection')
    box.space.order_collection:create_index('order_id_index',
        {type = 'tree', parts = {
            O_ORDER_ID_FN, 'string'
        }}
    )
    box.space.order_collection:create_index('user_id_index',
        {type = 'tree', unique = false, parts = {
            O_USER_ID_FN, 'string'
        }}
    )
end)

box.space.user_collection:replace(
    {1827767717, 'user_id_1', 'Ivan', 'Ivanov'})
box.space.user_collection:replace(
    {1827767717, 'user_id_2', 'Vasiliy', 'Pupkin'})
box.space.order_collection:replace(
    {'order_id_1', 'user_id_1', 'first order of Ivan'})
box.space.order_collection:replace(
    {'order_id_2', 'user_id_1', 'second order of Ivan'})
box.space.order_collection:replace(
    {'order_id_3', 'user_id_2', 'first order of Vasiliy'})

for i = 3, 100 do
    local s = tostring(i)
    box.space.user_collection:replace(
        {1827767717, 'user_id_' .. s, 'first name ' .. s, 'last name ' .. s})
    for j = (4 + (i - 3) * 40), (4 + (i - 2) * 40) - 1 do
        local t = tostring(j)
        box.space.order_collection:replace(
            {'order_id_' .. t, 'user_id_' .. s, 'order of user ' .. s})
    end
end

-- build accessor and graphql schemas
-- ----------------------------------

local accessor = graphql.accessor_space.new({
    schemas = schemas,
    collections = collections,
    service_fields = service_fields,
    indexes = indexes,
})

local gql_wrapper = graphql.new({
    schemas = schemas,
    collections = collections,
    accessor = accessor,
})

-- run queries
-- -----------

local query_1 = [[
    query user_by_order($order_id: String) {
        order_collection(order_id: $order_id) {
            order_id
            description
            user_connection {
                user_id
                last_name
                first_name
            }
        }
    }
]]

utils.show_trace(function()
    local variables_1 = {order_id = 'order_id_1'}
    local gql_query_1 = gql_wrapper:compile(query_1)
    local result = gql_query_1:execute(variables_1)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

local query_2 = [[
    query user_order($user_id: String, $first_name: String, $limit: Int,
            $offset: Long) {
        user_collection(user_id: $user_id, first_name: $first_name) {
            user_id
            last_name
            first_name
            order_connection(limit: $limit, offset: $offset) {
                order_id
                description
            }
        }
    }
]]

local gql_query_2

utils.show_trace(function()
    gql_query_2 = gql_wrapper:compile(query_2)

    local variables_2 = {user_id = 'user_id_1'}
    local result = gql_query_2:execute(variables_2)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

utils.show_trace(function()
    local variables_2_2 = {user_id = 'user_id_42', limit = 10, offset = 10}
    local result = gql_query_2:execute(variables_2_2)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

utils.show_trace(function()
    local variables_2_3 = {user_id = 'user_id_42', limit = 10, offset = 38}
    local result = gql_query_2:execute(variables_2_3)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

utils.show_trace(function()
    local variables_2_4 = {
        first_name = 'first name 42',
        limit = 3,
        offset = 39,
    }
    local result = gql_query_2:execute(variables_2_4)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

local query_3 = [[
    query users($limit: Int, $offset: Long) {
        user_collection(limit: $limit, offset: $offset) {
            user_id
            last_name
            first_name
        }
    }
]]

utils.show_trace(function()
    local variables_3 = {limit = 10, offset = 50}
    local gql_query_3 = gql_wrapper:compile(query_3)
    local result = gql_query_3:execute(variables_3)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

-- extra filter for 1:N connection
-- -------------------------------

local query_4 = [[
    query user_order($first_name: String, $description: String) {
        user_collection(first_name: $first_name) {
            user_id
            last_name
            first_name
            order_connection(description: $description) {
                order_id
                description
            }
        }
    }
]]

local gql_query_4 = gql_wrapper:compile(query_4)

-- should match 1 order
utils.show_trace(function()
    local variables_4_1 = {
        first_name = 'Ivan',
        description = 'first order of Ivan',
    }
    local result = gql_query_4:execute(variables_4_1)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

-- should match no orders
utils.show_trace(function()
    local variables_4_2 = {
        first_name = 'Ivan',
        description = 'non-existent order',
    }
    local result = gql_query_4:execute(variables_4_2)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

-- extra filter for 1:1 connection
-- -------------------------------

local query_5 = [[
    query user_by_order($first_name: String, $description: String) {
        order_collection(description: $description) {
            order_id
            description
            user_connection(first_name: $first_name) {
                user_id
                last_name
                first_name
            }
        }
    }
]]

local gql_query_5 = gql_wrapper:compile(query_5)

-- should match 1 user
utils.show_trace(function()
    local variables_5_1 = {
        first_name = 'Ivan',
        description = 'first order of Ivan',
    }
    local result = gql_query_5:execute(variables_5_1)
    print(('RESULT\n%s'):format(yaml.encode(result)))
end)

-- should match no users (or give an error?)
--utils.show_trace(function()
--    local variables_5_2 = {
--        first_name = 'non-existent user',
--        description = 'first order of Ivan',
--    }
--    local result = gql_query_5:execute(variables_5_2)
--    print(('RESULT\n%s'):format(yaml.encode(result)))
--end)

os.exit()
