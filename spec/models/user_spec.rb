# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, type: :model do
  let!(:create_member_permission) do
    create :permission,
           role: 'member'
  end
  context 'User model basic syntax' do
    ## Test of data length
    it { should validate_length_of(:data) }

    # 1100 char string
    let(:big_str) { "string bar"*11 }

    it { should_not allow_value(big_str).for(:data)}

    ## Test of validations
    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:password) }
    it { should have_many(:documents).dependent(:destroy) }

    ## Test of relationships
    it { should have_one(:profile).dependent(:destroy) }

    ## Test of UID creation
    it 'creates default uid with prefix ID' do
      default_user = create(:user)
      expect(default_user.uid).to start_with(ENV.fetch('BARONG_UID_PREFIX', 'ID'))
    end

    it 'uid prefix can be changed by ENV' do
      allow(Barong::App.config).to receive(:barong_uid_prefix).and_return('GG')

      default_user = create(:user)
      expect(default_user.uid).to start_with('GG')
    end

    it 'uid_prefix doesnt case sensitive and always converts to big letters' do
      allow(Barong::App.config).to receive(:barong_uid_prefix).and_return('aa')

      default_user = create(:user)
      expect(default_user.uid).to start_with('AA')
    end

    it do
      usr = create(:user)
      payload = usr.as_payload
      expect(payload['email']).to eq(usr.email)
    end

    describe '#referral' do
      let!(:user1) { create(:user) }
      let!(:user2) { create(:user, referral_id: user1.id) }

      it 'return error when referral doesnt exist' do
        record = User.new(uid: 'ID122312323', email: 'test@barong.io', password: 'Oo213Wqw')
        record.referral_id = 0
        record.valid?

        expect(record.errors[:referral_id]).to eq(['doesnt_exist'])
      end

      it 'return refferal uid' do
        expect(user2.referral_uid).to eq user1.uid
      end
    end
  end

  describe '#password' do
    it { should_not allow_value('Password1').for(:password)}
    it { should_not allow_value('Password1123').for(:password)}
    it { should_not allow_value('password').for(:password)}
    it { should_not allow_value('password1').for(:password)}
    it { should_not allow_value('Qq123123').for(:password)}
    it { should_not allow_value('QqQq123123').for (:password)}
    it { should_not allow_value('X2qL32').for(:password)}
    it { should_not allow_value('eoV0qu').for(:password)}
    it { should allow_value('Iequ4geiEWQw').for(:password)}
    it { should allow_value('Xwqe213PZCXwe').for(:password)}
    it { should allow_value('Kal31ewwqXrew').for(:password)}
  end

  let(:uploaded_file) { fixture_file_upload('/files/documents_test.jpg', 'image/jpg') }

  context 'User with 2 or more documents' do
    it do
      user = User.create!(email: 'test@gmail.com', password: 'KeeKi7zoWExzc')
      expect(User.count).to eq 1
      document1 = user.documents.create!(upload: uploaded_file,
                                            doc_type: 'Passport',
                                            doc_number: 'MyString',
                                            doc_expire: '01-01-2020')
      document2 = user.documents.create!(upload: uploaded_file,
                                            doc_type: 'Passport',
                                            doc_number: 'MyString',
                                            doc_expire: '01-02-2020')
      expect(user.reload.documents).to eq([document1, document2])
    end

    after(:all) { User.destroy_all }
  end

  describe 'Iso8601TimeFormat' do
    let!(:user) { create(:user) }
    around(:each) { |example| Time.use_zone('Pacific/Midway') { example.run } }

    it 'parses time in utc and iso8601' do
      expect(user.format_iso8601_time(user.created_at)).to \
        eq user.created_at.utc.iso8601
    end

    it 'skips nil' do
      expect(user.format_iso8601_time(nil)).to eq nil
    end

    it 'parses date to iso8601' do
      expect(user.format_iso8601_time(user.created_at.to_date)).to \
        eq user.created_at.to_date.iso8601
    end
  end

  describe 'States and labels dependency' do
    let(:reqs_list) { {} }
    let!(:create_permissions) do
      create :permission, role: 'member'
    end

    before do
      allow(BarongConfig).to receive(:list) { reqs_list }
    end

    context 'function testing' do
      let!(:user) { create(:user) }
      let!(:user_with_no_labels) { create(:user) }
      let!(:user_with_labels) do
        create(:label, user_id: user.id, key: 'email', value: 'verified', scope: 'private')
        create(:label, user_id: user.id, key: 'phone', value: 'verified', scope: 'private')
      end
      let(:reqs_list) {
        {
          "activation_requirements" => {
              "phone" => "verified",
              "documents" => "verified"
            },
          "state_triggers" => {
            "active_one_of_1_label" => ['email'],
            "active_one_of_3_labels" => ['first', 'second', 'third']
          }
        }
      }

      context 'labels_include?' do
        it { expect(user.labels_include?({ 'email' => 'verified' })).to be_truthy }

        it { expect(user.labels_include?({ 'email' => 'pending' })).to be_falsey }

        it { expect(user.labels_include?({ 'email' => 'verified', 'phone' => 'verified' })).to be_truthy }

        it { expect(user.labels_include?({ 'email' => 'verified', 'phone' => 'pending' })).to be_falsey }
      end

      context 'private_labels_to_hash' do
        it { expect(user.private_labels_to_hash).to eq({ 'email' => 'verified', 'phone' => 'verified' }) }

        it { expect(user_with_no_labels.private_labels_to_hash).to eq({}) }
      end
    end

    describe 'testing workability with ALL mapping type' do
      let!(:user) { create(:user, state: 'pending') }
      let(:reqs_list) {
        {
          "activation_requirements" => {
              "phone" => "verified",
              "documents" => "verified"
            },
          "state_triggers" => {
            "active_one_of_1_label" => ['email'],
            "active_one_of_3_labels" => ['first', 'second', 'third']
          }
        }
      }

      context 'changing state on adding label' do
        context 'sucessfully' do
          it 'changes state when only one label required' do
            # email required
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'email', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active_one_of_1_label')
          end

          it 'rollback from active to pending only in case of deleted one of activation reqs' do
            # [phone documents] required
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'phone', value: 'verified', scope: 'private')
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'documents', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active')

            user.labels.create(key: 'random', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active')

            user.labels.last.destroy
            expect(user.state).to  eq('active')

            user.labels.find_by_key('phone').destroy
            expect(user.state).to  eq('pending')
          end

          it 'changes state when 2 label required' do
            # [phone documents] required
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'phone', value: 'verified', scope: 'private')
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'documents', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active')
          end

          it 'changes state when one out of 3 label required' do
            # first or second third required
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'first', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active_one_of_3_labels')

            user.labels.find_by_key('first').destroy
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'third', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active_one_of_3_labels')

            user.labels.find_by_key('third').destroy
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'second', value: 'verified', scope: 'private')
            expect(user.state).to  eq('active_one_of_3_labels')
          end
        end

        context 'not enough labels' do
          it 'doesnt change state if provided 1 out of 2 labels only' do
            # [phone documents] required
            expect(user.state).to  eq('pending')

            user.labels.create(key: 'documents', value: 'verified', scope: 'private')
            expect(user.state).to  eq('pending')
          end
        end
      end

      context 'changing state on deleting' do
        context 'ALL policy' do
          let!(:give_user_active_state) do
            user.labels.create(key: 'phone', value: 'verified', scope: 'private')
            user.labels.create(key: 'documents', value: 'verified', scope: 'private')
          end

          it 'recalculates from active to  when remove all active labels' do
            expect(user.state).to  eq('active')
            Label.find_by(key: 'documents', user: user).destroy
            Label.find_by(key: 'phone', user: user).destroy

            user.reload

            expect(user.state).to eq('pending')
          end

          it 'recalculates from active_2_labels to active when pending one of active labels on ALL policy' do
            expect(user.state).to eq('active')
            Label.find_by(key: 'documents', user: user).destroy
            user.reload

            expect(user.state).to eq('pending')
          end
        end
      end
    end

    describe 'testing workability with ANY mapping type' do
      let!(:user) { create(:user, state: 'pending') }
      let(:reqs_list) {
        {
          "activation_requirements" => {
            "email" => "verified"
          },
          "state_triggers" => {
            "locked" => ['trade', 'withdraw']
          }
        }
      }

      context 'changing state on adding label' do
        context 'sucessfully' do
          it 'changes state when only when 1 label out of 2 matches' do
            expect(user.state).to eq('pending')

            user.labels.create(key: 'trade', value: 'suspicious', scope: 'private')
            expect(user.state).to eq('locked')
          end
        end

        context 'not enough labels' do
          it 'doesnt change state when no label matches' do
            expect(user.state).to eq('pending')
            user.labels.create(key: 'random', value: 'suspicious', scope: 'private')

            expect(user.state).to eq('pending')
          end
        end
      end

      context 'changing state on deleting' do
        context 'ANY policy' do
          let!(:give_user_locked_state) do
            user.labels.create(key: 'trade', value: 'suspicious', scope: 'private')
            user.labels.create(key: 'withdraw', value: 'suspicious', scope: 'private')
          end

          it 'doesnt recalculate state if remove one of ANY and another one of ANY still here with ANY policy' do
            expect(user.state).to eq('locked')

            user.labels.find_by(key: 'trade').destroy
            user.reload

            expect(user.state).to eq('locked')
          end

          it 'recalculates if removed all of ANY and there is no more match' do
            expect(user.state).to eq('locked')

            user.labels.find_by(key: 'trade').destroy
            user.labels.find_by(key: 'withdraw').destroy

            user.reload
            expect(user.state).to eq('pending')
          end
        end
      end
    end
  end
end
