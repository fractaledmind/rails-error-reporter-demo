# README

This is a sample Rails application to demonstrate the issue with the [error reporter]().

After the [initial `rails new` command](https://github.com/fractaledmind/rails-error-reporter-demo/commit/7b891493552adc25ef30fa9a3d5f1943dfb91a7e), the following steps were taken:

1. [Add a basic error reporter](https://github.com/fractaledmind/rails-error-reporter-demo/commit/5c2881f46069b06710f096ba011b9e341e1ff4ce)
2. [Add a basic route that throws an error if query param set](https://github.com/fractaledmind/rails-error-reporter-demo/commit/d10454ee14b49297b1562bda01e851c238e7f668)
3. [Allow non-SSL connections in production for local testing](https://github.com/fractaledmind/rails-error-reporter-demo/commit/3941949722eefb3d8242e2a05b3edb8ac392b105)

You can run the application in production mode via

```bash
RAILS_ENV=production rails server
```

If you visit `http://localhost:3000` you will see a simple "Hello, World!" message. If you visit `http://localhost:3000?error=true` you will see an error message.

In production mode, you will note that the error reporter is not called:

```bash
I, [2024-02-09T16:03:36.566702 #2067]  INFO -- : [206187db-f3e4-4edb-a473-d277dda95fb8] Started GET "/?error=true" for 127.0.0.1 at 2024-02-09 16:03:36 +0100
I, [2024-02-09T16:03:36.569307 #2067]  INFO -- : [206187db-f3e4-4edb-a473-d277dda95fb8] Processing by ApplicationController#root as HTML
I, [2024-02-09T16:03:36.569856 #2067]  INFO -- : [206187db-f3e4-4edb-a473-d277dda95fb8]   Parameters: {"error"=>"true"}
I, [2024-02-09T16:03:36.572014 #2067]  INFO -- : [206187db-f3e4-4edb-a473-d277dda95fb8] Completed 500 Internal Server Error in 2ms (ActiveRecord: 0.0ms | Allocations: 150)
E, [2024-02-09T16:03:36.573985 #2067] ERROR -- : [206187db-f3e4-4edb-a473-d277dda95fb8]
[206187db-f3e4-4edb-a473-d277dda95fb8] StandardError (This is a test exception):
[206187db-f3e4-4edb-a473-d277dda95fb8]
[206187db-f3e4-4edb-a473-d277dda95fb8] app/controllers/application_controller.rb:3:in `root'
```

Contrast that with running the application in development mode via:

```bash
RAILS_ENV=development rails server
```

You will see the error reporter is called:

```bash
Started GET "/?error=true" for ::1 at 2024-02-09 16:05:33 +0100
   (0.2ms)  CREATE TABLE "schema_migrations" ("version" varchar NOT NULL PRIMARY KEY)
   (0.1ms)  CREATE TABLE "ar_internal_metadata" ("key" varchar NOT NULL PRIMARY KEY, "value" varchar, "created_at" datetime(6) NOT NULL, "updated_at" datetime(6) NOT NULL)
  ActiveRecord::SchemaMigration Load (0.1ms)  SELECT "schema_migrations"."version" FROM "schema_migrations" ORDER BY "schema_migrations"."version" ASC
Processing by ApplicationController#root as HTML
  Parameters: {"error"=>"true"}
Completed 500 Internal Server Error in 1ms (ActiveRecord: 0.0ms | Allocations: 1374)


****************************************************************************************************
ERROR REPORTED

StandardError (This is a test exception):

app/controllers/application_controller.rb:3:in `root'
```

## In-Depth Analysis

I have dug in more, and I have a clearer picture of what is going on. The top-level point is that **it is mostly a happy coincidence that errors are reported in development**. But, let me explain.

Errors are reported via the `ActionDispatch::Executor` middleware:
https://github.com/rails/rails/blob/3b8222ccd0f38a95109db2e84ee228318d322877/actionpack/lib/action_dispatch/middleware/executor.rb#L11-L21

You will notice that only _raised_ errors are reported, as we are inside of a `rescue` block. The issue is that, by default, errors are not _raised_, they are _rendered_. This is what happens in the `ActionDispatch::ShowExceptions` middleware:
https://github.com/rails/rails/blob/3b8222ccd0f38a95109db2e84ee228318d322877/actionpack/lib/action_dispatch/middleware/show_exceptions.rb#L30-L41

Inside of this middleware, inside of a `rescue` block, we see a condition—the error is either _rendered_ or _raised_. The determinant is the result of `ActionDispatch::ExceptionWrapper#show?`:
https://github.com/rails/rails/blob/3b8222ccd0f38a95109db2e84ee228318d322877/actionpack/lib/action_dispatch/middleware/exception_wrapper.rb#L177-L191

You can inspect the `config` variable, but you will find (as I did) that by default, for both `development` and `production` is `:all`. Thus, the `else` condition is hit and `true` is returned. This is the first major detail: **in both `development` and `production` environments, errors are _rendered_ by the `ShowExceptions` middleware**.

So, the question becomes, how are errors reported in `development`? The short answer is because `development` includes the `ActionDispatch::Reloader` middleware and `production` does not. But, for those looking to understand what is occurring with more detail, let me elaborate.

In a standard, default Rails application, you will find the following middleware stack in `development`:
```irb
irb(main):001> Rails.application.middleware
=>
#<ActionDispatch::MiddlewareStack:0x0000000105ce77e0
 @middlewares=
  [ActionDispatch::HostAuthorization,
   Rack::Sendfile,
   ActionDispatch::Static,
   ActionDispatch::Executor,
   ActionDispatch::ServerTiming,
   ActiveSupport::Cache::Strategy::LocalCache::Middleware,
   Rack::Runtime,
   Rack::MethodOverride,
   ActionDispatch::RequestId,
   ActionDispatch::RemoteIp,
   Rails::Rack::Logger,
   ActionDispatch::ShowExceptions,
   WebConsole::Middleware,
   ActionDispatch::DebugExceptions,
   ActionDispatch::ActionableExceptions,
   ActionDispatch::Reloader,
   ActionDispatch::Callbacks,
   ActiveRecord::Migration::CheckPending,
   ActionDispatch::Cookies,
   ActionDispatch::Session::CookieStore,
   ActionDispatch::Flash,
   ActionDispatch::ContentSecurityPolicy::Middleware,
   ActionDispatch::PermissionsPolicy::Middleware,
   Rack::Head,
   Rack::ConditionalGet,
   Rack::ETag,
   Rack::TempfileReaper]>
```

In comparison, you will see this middleware stack in `production`:
```irb
irb(main):001> Rails.application.middleware
=>
#<ActionDispatch::MiddlewareStack:0x000000010943fc60
 @middlewares=
  [Rack::Sendfile,
   ActionDispatch::Static,
   ActionDispatch::Executor,
   Rack::Runtime,
   Rack::MethodOverride,
   ActionDispatch::RequestId,
   ActionDispatch::RemoteIp,
   Rails::Rack::Logger,
   ActionDispatch::ShowExceptions,
   ActionDispatch::DebugExceptions,
   ActionDispatch::Callbacks,
   ActionDispatch::Cookies,
   ActionDispatch::Session::CookieStore,
   ActionDispatch::Flash,
   ActionDispatch::ContentSecurityPolicy::Middleware,
   ActionDispatch::PermissionsPolicy::Middleware,
   Rack::Head,
   Rack::ConditionalGet,
   Rack::ETag,
   Rack::TempfileReaper]>
```

Diffing these two arrays (`dev.map(&:inspect) - prod.map(&:inspect)`), we see that `development` includes these additional middlewares:
```irb
["ActionDispatch::HostAuthorization",
 "ActionDispatch::ServerTiming",
 "ActiveSupport::Cache::Strategy::LocalCache::Middleware",
 "WebConsole::Middleware",
 "ActionDispatch::ActionableExceptions",
 "ActionDispatch::Reloader",
 "ActiveRecord::Migration::CheckPending"]
```

One of these middlewares allows errors to be reported. When adding additional logging to the middlewares, it became clear that errors were reported in `development` because **2 instances of `ActionDispatch::Executor` are in the middleware stack**. The inner instance sees the raised exception before the `ShowExceptions` middleware swallows it to render an error HTTP response. This second, inner instance of the `Executor` is, in fact, the `ActionDispatch::Reloader` middleware:
https://github.com/rails/rails/blob/3b8222ccd0f38a95109db2e84ee228318d322877/actionpack/lib/action_dispatch/middleware/reloader.rb#L3-L14

It inherits from the `Executor` and does nothing else. I confess that I don't presently understand how a second instance of the `Executor` middleware "wraps the request with callbacks provided by `ActiveSupport::Reloader`", but that is immaterial to our investigation. The essential details is that:

> [!IMPORTANT]
> Errors that occur within the HTTP request->response lifecycle are only reported in `development` _if_ `config.enable_reloading` is set to `true`. If set to `false`, you will observe in that the error reporter is **not** called.
