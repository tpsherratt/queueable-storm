# Queueable

Queuable is useful when you have a model that represents a unit of work that needs doing. 
It:
* Makes your model processable with sidekiq
* Adds state tracking (eg. status codes, processed_at timestamp)
* Error handling/storage
* Filtering of jobs

## Usage
Add the requesite fields to your model:
```ruby
class AddQueueableFieldsToMyModel < ActiveRecord::Migration
  def change
    add_column :my_models, :status, :integer
    add_column :my_models, :attempts, :integer
    add_column :my_models, :processed_at, :timestamp
    add_column :my_models, :ers, :text
  end
end

```

Setup your model
```ruby
module MyModule
  class MyJob < Storm::BaseModel
    include Queueable
    
    # ...
    
    # Set options
    queueable manager: MyModule::MyJobManager, run_method: :do_work #, worker: MyWorker
    
    def do_work
      # The actual method that does the job
      # Return true for success
      # Return false for rejected (ie. not an error, but processing could not continue for some reason)
    end
    
    def filter?
      # if method present and returns true job will not be processed
    end
    
    def ready?
      # if method present and returns false job will be retried in n**2 seconds
    end
  end
end
```

Go
```ruby
MyModule::MyJobManager.first.process
```
This will
* Create a sidekiq job
* Call the `filter?` and `ready?` methods if present.
* Call your run method, in the above case `do_work`
    
### Configuration
Config is set with the `queueable ...` line in your model.
* `manager` - required. Defines the model's managed.
* `run_method` - optional. Default: `:run`. Defines the method that should be called to do the work.
* `worker` - optional. Defines the sidekiq worker that should be used. If not specified, the default Queueable worker is used.

### Statuses
The state of each job is stored in the status column. Possible statuses are as follows:

```
DONE = 0        # successfully processed
PROCESSING = 1  # currently being processed
QUEUED = 2      # waiting to be processed, could be after :ready? returned false
FILTERED = 4    # :filter? returned true
REJECTED = 5    # run method returned false, job was not completed correctly
ERRORED = 9     # exception while processing, look in :ers to see waht happened
```

Jobs with statuses `QUEUED`, `FILTERED`, or `ERRORED` can be rerun.
Jobs with statuses `DONE`, `PROCESSING`, or `REJECTED` cannot be rerun.

### Errors
If a job errors, the exception will be caught, it's status will be set to 9 and the trace will be stored in `ers`. The error will then be rethrown, so sidekiq shows it as an error.


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'queueable'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install queueable

## Usage

TODO: Write usage instructions here

## Contributing

1. Fork it ( https://github.com/[my-github-username]/queueable/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
