import http from 'k6/http';
import { Httpx } from 'https://jslib.k6.io/httpx/0.1.0/index.js';
//import tracing, { Http } from 'k6/x/tracing';
import { sleep,check} from 'k6';
import { Counter } from "k6/metrics";

/**
 * Hipster workload generator by k6
 * @param __ENV.FRONTEND_ADDR, __ENV.OTLP_SERVICE_ADDR, __ENV.OTLP_SERVICE_PORT
 * @constructor hrexed
 */

let errors = new Counter("errors");

export let options = {
    discardResponseBodies: true,
};

const baseurl = `http://${__ENV.FRONTEND_ADDR}`;

const host_header = `${__ENV.HOST_HEADER}`;


const tasks = {
    "users": 1,
    "createusers": 2,
    "todos": 5,
    "posts": 2,
    "createposts": 3,
};


const waittime = [1,2,3,4,5,6,7,8,9,10]

const url=`${__ENV.OTLP_SERVICE_ADDR}`;

function randomestring(length) {
    let result = '';
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    const charactersLength = characters.length;
    let counter = 0;
    while (counter < length) {
    result += characters.charAt(Math.floor(Math.random() * charactersLength));
    counter += 1;
    }
    return result;
}

/*export function setup() {
  console.log(`Running xk6-distributed-tracing v${tracing.version}`);
}*/
export default function() {

    const session = new Httpx({
      baseURL: baseurl,
      timeout: 20000, // 20s timeout.
    });
    session.addHeader('Host', host_header);
   /* const http = new Http({
        exporter: "otlp",
        propagator: "w3c",
        endpoint: url
      });*/

    //Access index page
    for ( let i=0; i<tasks["todos"]; i++)
    {
        let res = session.get(`/todos`);
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }

    //Access setCurrency page
    for ( let i=0; i<tasks["createusers"]; i++)
    {
        let email = 'test@'+ randomestring(8) + ".com";
        const first = ['john', 'paul', 'joe', 'eric','jessica'];
        const last = ['deferf', 'dddddet', 'doe', 'bush','macron'];
        let res = session.post(`/users`, {
            'firstName': first[Math.floor(Math.random() * first.length)] ,
            'lastName': randomestring(8),
            'email': email
        });
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }
    for ( let i=0; i<tasks["users"]; i++)
    {
        let res = session.get(`/users`);
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }
    //Access browseProduct page
    for ( let i=0; i<tasks["todos"]; i++)
    {
        let res = session.get(`/todos`);
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])
    }

    //Access addToCart page
    const user = ['1', '2', '3',];
    for ( let i=0; i<tasks["createposts"]; i++)
    {
         let res = session.post(`/posts`, {
           'title': randomestring(15),
           'body': randomestring(30),
           'author_id': user[Math.floor(Math.random() * user.length)]
       });
        let checkRes = check(res, { "status is 200": (r) => r.status === 200 });

        // show the error per second in grafana
        if (checkRes === false ){
            errors.add(1);
        }
        sleep(waittime[Math.floor(Math.random() * waittime.length)])

       res = session.get(`/posts`);
       checkRes = check(res, { "status is 200": (r) => r.status === 200 });



      sleep(waittime[Math.floor(Math.random() * waittime.length)])

    }


}
export function teardown(){
  // Cleanly shutdown and flush telemetry when k6 exits.
  tracing.shutdown();
}
