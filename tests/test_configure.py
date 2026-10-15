import unittest
from deploy.configure import verified_owner


class OwnerVerificationTests(unittest.TestCase):
    def test_only_matching_start_and_connection(self):
        updates = [
            {'message':{'from':{'id':42},'chat':{'type':'private'},'text':'/start'}},
            {'message':{'from':{'id':99},'chat':{'type':'private'},'text':'/start'}},
            {'business_connection':{'user':{'id':42},'is_enabled':True}}]
        self.assertEqual(verified_owner(updates,None),42)

    def test_disconnected_or_ambiguous_rejected(self):
        updates = [{'message':{'from':{'id':42},'chat':{'type':'private'},'text':'/start'}}]
        with self.assertRaises(ValueError):
            verified_owner(updates,None)
        updates.extend([{'business_connection':{'user':{'id':42},'is_enabled':True}},
                        {'message':{'from':{'id':99},'chat':{'type':'private'},'text':'/start'}},
                        {'business_connection':{'user':{'id':99},'is_enabled':True}}])
        with self.assertRaises(ValueError):
            verified_owner(updates,None)
