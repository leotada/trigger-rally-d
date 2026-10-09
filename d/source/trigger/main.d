// main [trigger]
//
// Copyright 2004-2006 Jasmine Langridge, jas@jareiko.net
// License: GPL version 2 (see included gpl.txt)
module trigger.main;

import trigger.mainapp;

int main(string[] args)
{
  auto app = new MainApp("Trigger Rally", ".trigger-rally");
  return app.run(args);
}
