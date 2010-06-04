require File.join( File.dirname(__FILE__), '..', "spec_helper" )

describe Fee do
  before(:all) do
    Payment.all.destroy! if Payment.all.count > 0
    Client.all.destroy! if Client.count > 0
    @user = User.new(:login => 'Joey', :password => 'password', :password_confirmation => 'password')
    @user.role = :admin
    @user.save
    @user.should be_valid

    @manager = StaffMember.new(:name => "Mrs. M.A. Nerger")
    @manager.save
    @manager.should be_valid

    @funder = Funder.new(:name => "FWWB")
    @funder.save
    @funder.should be_valid

    @funding_line = FundingLine.new(:amount => 10_000_000, :interest_rate => 0.15, :purpose => "for women", :disbursal_date => "2006-02-02", :first_payment_date => "2007-05-05", :last_payment_date => "2009-03-03")
    @funding_line.funder = @funder
    @funding_line.save
    @funding_line.should be_valid

    @branch = Branch.new(:name => "Kerela branch")
    @branch.manager = @manager
    @branch.code = "BR"
    @branch.save
    @branch.should be_valid

    @center = Center.new(:name => "Munnar hill center")
    @center.manager = @manager
    @center.branch  = @branch
    @center.code = "CE"
    @center.save
    @center.errors.each {|e| puts e}
    @center.should be_valid

    @client_type  =  ClientType.first||ClientType.create(:type => "standard")

    @client = Client.new(:name => 'Ms C.L. Ient', :reference => Time.now.to_s, :client_type => @client_type, :created_by => @user)
    @client.center  = @center
    @client.date_joined = Date.parse('2006-01-01')
#    @client.type_of_account = :savings
    @client.save
    @client.errors.each {|e| puts e}
    @client.should be_valid
    # validation needs to check for uniqueness, therefor calls the db, therefor we dont do it
    @loan_product = LoanProduct.new
    @loan_product.name = "LP1"
    @loan_product.max_amount = 1000
    @loan_product.min_amount = 1000
    @loan_product.max_interest_rate = 100
    @loan_product.min_interest_rate = 0.1
    @loan_product.installment_frequency = :weekly
    @loan_product.max_number_of_installments = 25
    @loan_product.min_number_of_installments = 25
    @loan_product.loan_type = "DefaultLoan"
    @loan_product.valid_from = Date.parse('2000-01-01')
    @loan_product.valid_upto = Date.parse('2012-01-01')
    @loan_product.save
    @loan_product.errors.each {|e| puts e}
    @loan_product.should be_valid
    @loan = Loan.new(:amount => 1000, :interest_rate => 0.2, :installment_frequency => :weekly, :number_of_installments => 25, :scheduled_first_payment_date => "2000-12-06", :applied_on => "2000-02-01", :scheduled_disbursal_date => "2000-06-13")
    @loan.history_disabled = true
    @loan.applied_by       = @manager
    @loan.funding_line     = @funding_line
    @loan.client           = @client
    @loan.loan_product     = @loan_product
    @loan.valid?
    @loan.errors.each {|e| puts e}
    @loan.should be_valid
    @loan.save
  end


  before :each do
    @f = Fee.new
    @f.name = "Test Fee"
    @f.payable_on = :loan_applied_on
    @f.amount = 1000
    @f.should be_valid
    @f.amount = nil
  end

  it "should have a name" do
    @f.name = nil
    @f.should_not be_valid
  end

  it "should have either an amount or a percentage" do
    @f.amount = @f.percentage = nil
    @f.should_not be_valid
    @f.amount = 1000
    @f.should be_valid
    @f.errors.each {|e| puts e}
    @f.amount = nil
    @f.percentage = 0
    @f.should be_valid
  end

  it "should never return less than min_amount" do
    @f.min_amount = 1000
    @f.fees_for(@loan).should == 1000
  end

  it "should never return more than max_amount" do
    @f.percentage = 1
    @f.max_amount = 1
    @f.fees_for(@loan).should == 1
  end


  it "should return correct fee_schedule for loan" do
    @f.percentage = 0.1
    @loan_product.fees << @f 
    @loan.fee_schedule.should == {@loan.applied_on => {"Test Fee" => 100}}
    @f2 = Fee.new(:name => "Other Fee")
    @f2.amount = 111
    @f2.payable_on = :loan_scheduled_first_payment_date
    @loan_product.fees << @f2
    @loan.fee_schedule.should == {@loan.applied_on => {"Test Fee" => 100}, @loan.scheduled_first_payment_date => {"Other Fee" => 111}}
  end
  
  it "should return correct fee_schedule for multiple fees even on the same date" do
    @f2 = Fee.new(:name => "Other Fee")
    @f2.amount = 111
    @f2.payable_on = :loan_applied_on
    @f2.should be_valid
    @f.percentage = 0.1
    @loan_product.fees = [@f, @f2]
    @loan.fee_schedule.should == {@loan.applied_on => {"Test Fee" => 100, "Other Fee" => 111}}
  end

  it "should return correct fees payable" do
    @f2 = Fee.new(:name => "Other Fee")
    @f2.amount = 111
    @f2.payable_on = :loan_applied_on
    @f2.should be_valid
    @f.percentage = 0.1
    @loan.fees_payable_on.should == {"Test Fee" => 100, "Other Fee" => 111}
  end


  it "should return correct fees_paid" do
    @f2 = Fee.new(:name => "Other Fee")
    @f2.amount = 111
    @f2.payable_on = :loan_applied_on
    @f2.should be_valid
    @f.percentage = 0.1
#    @loan_product.fees << @f
#    @loan_product.fees << @f2
    @p = Payment.new(:amount => 20, :received_on => '2009-01-01', :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :loan => @loan, :comment => "Test Fee")
    @p.valid?
    @p.errors.each {|e| puts e}
    @p.should be_valid
    @p.save
    @loan.fees_paid.should == {Date.parse('2009-01-01') => {"Test Fee" => 20}}
    @loan.total_fees_payable_on.should == 111 + 80
    @loan.fees_payable_on.should == {"Test Fee" => 80, "Other Fee" => 111}
    @p = Payment.new(:amount => 20, :received_on => '2009-01-01', :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :loan => @loan, :comment => "Other Fee")
    @p.save
    @loan.total_fees_payable_on.should == 111 + 100 - 40
    @loan.fees_paid.should == {Date.parse('2009-01-01') => {"Test Fee" => 20, "Other Fee" => 20}}
    @loan.fees_payable_on.should == {"Test Fee" => 80, "Other Fee" => 91}
  end    

  it "should give correct fee schedule for client" do
    @client_fee = Fee.new(:name => "client Fee", :amount => 20, :payable_on => :client_date_joined)
    @client_fee.save
    @client_fee.errors.each {|e| puts e}
    @client_fee.should be_valid
    @client.fee_schedule.should == {@client.date_joined => {"client Fee" => 20}}
    @client.total_fees_payable_on(@client.date_joined - 1).should == 0
    @client.total_fees_payable_on(@client.date_joined).should == 20
    @client.fees_payable_on.should == {"client Fee" => 20}
    @p = Payment.new(:amount => 10, :received_on => @client.date_joined - 1, :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :comment => "client Fee")
    @p.should_not be_valid # trying to pay fee before it is due
    @p = Payment.new(:amount => 10, :received_on => @client.date_joined, :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :comment => "client Fee")
    @p.save
    @p.errors.each {|e| puts e}
    @p.should be_valid
    @client.fees_paid.should == {@client.date_joined => {"client Fee" => 10}}
    @client.fees_payable_on.should == {"client Fee" => 10}
  end
  it "should work just as well for another fee" do
    Payment.all(:client => @client, :loan => nil).destroy!
    @client_fee = Fee.new(:name => "client Fee", :amount => 20, :payable_on => :client_date_joined)
    @client_fee2 = Fee.new(:name => "grt Fee", :amount => 10, :payable_on => :client_grt_pass_date)
    @client_fee2.save
    @client_fee2.errors.each {|e| puts e}
    @client_fee2.should be_valid
    @client.grt_pass_date = Date.today
    @client.fee_schedule.should == {@client.date_joined => {"client Fee" => 20}, Date.today => {"grt Fee" => 10}}
    @client.total_fees_payable_on(Date.today - 1).should == 20
    @client.total_fees_payable_on(Date.today).should == 30
    @client.fees_payable_on.should == {"client Fee" => 20, "grt Fee" => 10}
    @p = Payment.new(:amount => 20, :received_on => @client.date_joined, :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :comment => "client Fee")
    @p.should be_valid 
    @p.save
    @p = Payment.new(:amount => 5, :received_on => Date.today - 1, :type => :fees, :client => @client,
                     :received_by => @manager, :created_by => @user, :comment => "grt Fee")
    @p.should_not be_valid # trying to pay fee before it is due
    @p.received_on = Date.today
    @p.should be_valid
    @p.save
    @client.fees_paid.should == {@client.date_joined => {"client Fee" => 20}, Date.today => {"grt Fee" => 5}}
    @client.fees_payable_on.should == {"client Fee" => 0, "grt Fee" => 5}

  end

  it "should pay client fees correctly" do
    Payment.all.destroy!
    Fee.all.destroy!
    @client_fee = Fee.new(:name => "client Fee", :amount => 20, :payable_on => :client_date_joined)
    @client_fee.save
    @client_fee2 = Fee.new(:name => "grt Fee", :amount => 10, :payable_on => :client_grt_pass_date)
    @client_fee2.save
    @client.grt_pass_date = Date.today
    @client.pay_fees(5, Date.today, @manager, @user)
    @client.fees_payable_on.should == {"client Fee" => 20 - 5, "grt Fee" => 10}
  end


end
