require 'rails_helper.rb'

describe 'PasswordTest', type: :feature do
  
  after(:each) { Warden.test_reset! } 
  let(:user) { FactoryGirl.create(:user) }
  let(:identity) { Identity.create(email: user.email, password: 'wakka-wakka') }
  let(:user_without_identity) { FactoryGirl.create(:user) }

  it 'can request a password recovery' do
    expect(identity.email).to eq(user.email)
    Devise.stub(:friendly_token).and_return("ToAvAl0n")
    visit new_user_password_path
    expect(page).to have_content("Forgot your password?")
    fill_in 'user_email', with: user.email
    expect { click_button 'Send me reset password instructions' }
      .to change { ActionMailer::Base.deliveries.count }.by(1)

    expect(page).to have_current_path("/users/auth/identity")
    expect(page).to have_content("You will receive an email with instructions about how to reset your password in a few minutes")
    mail = ActionMailer::Base.deliveries.last.body.encoded
    expect(mail).to have_content("Hello #{user.email}!")

    visit edit_user_password_path(reset_password_token: "ToAvAl0n")
    fill_in 'New password', with: '2avalon'
    fill_in 'Confirm new password', with: '2avalon'
    click_button 'Change my password'

    expect(page).to have_current_path('/')
    expect(page).to have_content("Your password was changed successfully")
    expect(page).to have_content("You are now signed in")
    expect(page).to have_content(user.username)
    expect(identity.reload.authenticate('2avalon')).not_to be_falsey
  end

  it 'can not request a password recovery if the account doesnt have an identity' do
    visit new_user_password_path
    expect(user_without_identity).not_to receive(:send_reset_password_instructions) 
    expect(page).to have_content("Forgot your password?")
    fill_in 'user_email', with: user_without_identity.email

    expect { click_button 'Send me reset password instructions' }
      .to change { ActionMailer::Base.deliveries.count }.by(0)

    expect(page).to have_current_path("/users/auth/identity")
    expect(page).to have_content("Sorry, but it is not possible to reset your password on your account")
  end
end
