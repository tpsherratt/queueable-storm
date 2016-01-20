require 'spec_helper'
require 'sidekiq'
require 'storm'

describe Queueable, broken: true do
	# shit to create and drop a dummy table that is required because the
	# module requires active record shit...
  before :all do
    ActiveRecord::Base.establish_connection(
      adapter: 'sqlite3',
      database: 'storm_test.sqlite3'
    )

    m = ActiveRecord::Migration
    m.verbose = false  
    m.create_table :queueable_dummy_class_records do |t| 
      t.integer :status
      t.integer :attempts
      t.timestamp :processed_at
      t.text :ers
    end
  end

  after :all do
    m = ActiveRecord::Migration
    m.verbose = false
    m.drop_table :queueable_dummy_class_records
  end

	class QueueableDummyClassRecord < ActiveRecord::Base
		serialize :ers, Array
	end

	class QueueableDummyClassManager < Storm::BaseManager
#		include Queueable::StormManager

		# rspec is stupid
		def find(i); end
	end

	class QueueableDummyClass < Storm::BaseModel
		include Queueable

		queueable manager: QueueableDummyClassManager

		def filter?; false end
		def ready?; true end

		def run
			true
		end
	end

	context 'class methods' do
		# TODO: the state doesn't get reset after I fuck about with it in these tests,
		# so lots below fail. Not sure how to test this. TS
		#
		# describe 'queueable' do
		# 	it 'populates the @worker var' do
		# 		@double = double("worker")
		# 		QueueableDummyClass.queueable(worker: @double)
		# 		QueueableDummyClass.worker).to eq(@double)
		# 	end
		# 	it 'populates the @run_method var' do
		# 		@double = double("worker")
		# 		QueueableDummyClass.queueable(run_method: @double)
		# 		QueueableDummyClass.run_method).to eq(@double)
		# 	end
		# end

		describe 'run' do
			before :each do
				@q = QueueableDummyClass.new
				allow(@q).to receive(:processable?).and_return(true)
				allow_any_instance_of(QueueableDummyClassManager).to receive(:find).and_return(@q)
				#@m.stub(:destroy)
			end
			it 'does not run unless resource is processable?' do
				expect(@q).to receive(:processable?).and_return(false)
				expect(@q).not_to receive(:status=)
				QueueableDummyClass.run(1)
			end
			it 'updates status to PROCESSING while it is processing' do
				expect(@q).to receive(:status=).with(Queueable::PROCESSING).and_call_original
				expect(@q).to receive(:processed_at=).with(kind_of(Time))
				expect(@q).to receive(:status=).with(Queueable::DONE).and_call_original
				QueueableDummyClass.run(1)
			end
			it 'exits with status filtered if filter? is defined and returns true' do
				expect(@q).to receive(:filter?).and_return(true)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::FILTERED)
			end
			it 'continues processing if filter? is defined and returns false' do
				expect(@q).to receive(:filter?).and_return(false)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::DONE)
			end
			it 'is hap even if filter? is not defined' do
				# having nothing receive :filter? here means it's not defined
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::DONE)
			end
			it 'exits with status QUEUED, attempts +=1 if ready? is defined and returns false' do
				@q.attempts = 1
				expect(@q).to receive(:ready?).and_return(false)
				expect(@q).to receive(:process)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::QUEUED)
				expect(@q.attempts).to eq(2)
			end
			it 'continues processing if ready? is defined and returns true' do
				expect(@q).to receive(:ready?).and_return(true)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::DONE)
			end
			it 'is hap even if ready? is not defined' do
				# having nothing to receive :ready? here means it's not defined
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::DONE)
			end
			it 'sends @run method to the resource' do
				expect(@q).to receive(QueueableDummyClass.run_method)
				QueueableDummyClass.run(1)
			end
			it 'exits with status ERRORED if run_method throws' do
				expect(@q).to receive(QueueableDummyClass.run_method).and_raise(Exception)
				expect(lambda{ QueueableDummyClass.run(1) }).to raise_exception
				expect(@q.status).to eq(Queueable::ERRORED)
				expect(@q.ers.length).to eq(2)
			end
			it 'exits with status DONE if run_method returns true' do
				expect(@q).to receive(QueueableDummyClass.run_method).and_return(true)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::DONE)
			end
			it 'exits with status REJECTED if run_method returns false' do
				expect(@q).to receive(QueueableDummyClass.run_method).and_return(false)
				QueueableDummyClass.run(1)
				expect(@q.status).to eq(Queueable::REJECTED)
			end
		end
	end

	context 'class_eval shit' do
		before :each do
			@m = QueueableDummyClassManager.new
		end
		it 'sets set_status as a callback' do
			@q = QueueableDummyClass.new
			expect(@q).to receive(:set_status).and_call_original
			@m.save @q
		end
		it 'sets set_attempts as a callback' do
			@q = QueueableDummyClass.new
			expect(@q).to receive(:set_attempts).and_call_original
			@m.save @q
		end
		it 'sets a default value for @worker' do
			expect(QueueableDummyClass.worker).to eq(Queueable::Worker)
		end
		it 'sets a default value for @run_method' do
			expect(QueueableDummyClass.run_method).to eq(:run)
		end
	end

	describe 'set_status' do
		it 'should set the status to Queueable::QUEUED' do
			@q = QueueableDummyClass.new
			expect(@q.status).to be_nil
			@q.set_status
			expect(@q.status).to eq(Queueable::QUEUED)
		end
	end

	describe 'set_attempts' do
		it 'should set the attempts to 0' do
			@q = QueueableDummyClass.new
			expect(@q.attempts).to be_nil
			@q.set_attempts
			expect(@q.attempts).to eq(0)
		end
	end

	describe 'is_queueable?' do
		it 'should return true' do
			expect(QueueableDummyClass.new.is_queueable?).to be_truthy
		end
	end

	describe 'process' do
		before :each do
			@q = QueueableDummyClass.new
			allow(@q).to receive(:id).and_return(4)
		end
		it 'should call perform_async on the worker if attempts = 0' do
			@q.attempts = 0
			expect(QueueableDummyClass.worker).to receive(:perform_async).with(QueueableDummyClass.name, 4)
			expect(QueueableDummyClass.worker).not_to receive(:perform_in)
			@q.process
		end
		it 'should call perform_in on the worker if attempts > 0' do
			@q.attempts = 1
			expect(QueueableDummyClass.worker).to receive(:perform_in).with(2, QueueableDummyClass.name, 4)
			expect(QueueableDummyClass.worker).not_to receive(:perform_async)
			@q.process
		end
	end

	describe 'status convenience methods' do
		before :each do
			@ni = QueueableDummyClass.new
		end
		it 'should return false if status is done' do
			@ni.status = Queueable::DONE
			expect(@ni.done?).to be_truthy
			expect(@ni.finished_processing?).to be_truthy
			expect(@ni.processable?).to be_falsey
		end
		it 'should return false if status is rejected' do
			@ni.status = Queueable::REJECTED
			expect(@ni.done?).to be_falsey
			expect(@ni.finished_processing?).to be_truthy
			expect(@ni.processable?).to be_falsey
		end
		it 'should return false if status is processing' do
			@ni.status = Queueable::PROCESSING
			expect(@ni.done?).to be_falsey
			expect(@ni.finished_processing?).to be_falsey
			expect(@ni.processable?).to be_falsey
		end
		it 'should return false if status is filtered' do
			@ni.status = Queueable::FILTERED
			expect(@ni.done?).to be_falsey
			expect(@ni.finished_processing?).to be_truthy
			expect(@ni.processable?).to be_truthy
		end
		it 'should return true if status is ERRORED' do
			@ni.status = Queueable::ERRORED
			expect(@ni.done?).to be_falsey
			expect(@ni.finished_processing?).to be_falsey
			expect(@ni.processable?).to be_truthy
		end
		it 'should return false if status is processable' do
			@ni.status = Queueable::QUEUED
			expect(@ni.done?).to be_falsey
			expect(@ni.finished_processing?).to be_falsey
			expect(@ni.processable?).to be_truthy
		end
	end
end
